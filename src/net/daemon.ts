// Daemon entry: listens on /tmp/ching.sock, owns the room registry, routes
// messages between sockets and Room instances. Server-authoritative RNG.

import { existsSync, unlinkSync, chmodSync } from 'node:fs';
import * as net from 'node:net';
import { randomUUID } from 'node:crypto';
import type { Rng } from '../engine.js';
import {
  FrameDecoder,
  ProtocolError,
  encode,
  type C2S,
  type S2C,
} from './protocol.js';
import { Room, RoomError, type RoomEvent } from './room.js';

export const DEFAULT_SOCK = '/tmp/ching.sock';

const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // excludes 0,O,I,L,1
const CODE_LEN = 4;
const TICK_MS = 1_000;

type Conn = {
  id: string;
  socket: net.Socket;
  decoder: FrameDecoder;
  token: string | null;
  name: string | null;
  roomCode: string | null;
};

export type DaemonDeps = {
  rng?: Rng;
  now?: () => number;
  log?: (line: object) => void;
};

export class Daemon {
  private rooms = new Map<string, Room>();
  private conns = new Map<string, Conn>();
  private tickHandle: NodeJS.Timeout | null = null;
  private server: net.Server | null = null;
  private readonly rng: Rng;
  private readonly now: () => number;
  private readonly log: (line: object) => void;

  constructor(deps: DaemonDeps = {}) {
    this.rng = deps.rng ?? Math.random;
    this.now = deps.now ?? Date.now;
    this.log = deps.log ?? ((line) => console.log(JSON.stringify(line)));
  }

  // ─── lifecycle ────────────────────────────────────────────────────────────
  async listen(sockPath: string = DEFAULT_SOCK): Promise<void> {
    await this.cleanStaleSocket(sockPath);
    await new Promise<void>((resolve, reject) => {
      const server = net.createServer((socket) => this.acceptConn(socket));
      server.on('error', reject);
      server.listen(sockPath, () => {
        try { chmodSync(sockPath, 0o660); } catch {}
        this.server = server;
        resolve();
      });
    });
    this.tickHandle = setInterval(() => this.tickRooms(), TICK_MS);
    this.log({ ts: this.now(), level: 'info', msg: 'daemon listening', sock: sockPath });
  }

  async close(reason = 'server shutting down'): Promise<void> {
    if (this.tickHandle) {
      clearInterval(this.tickHandle);
      this.tickHandle = null;
    }
    for (const c of this.conns.values()) {
      this.sendRaw(c, { v: 1, t: 'BYE', reason });
      c.socket.end();
    }
    if (this.server) {
      await new Promise<void>((resolve) => this.server!.close(() => resolve()));
      this.server = null;
    }
  }

  private async cleanStaleSocket(sockPath: string): Promise<void> {
    if (!existsSync(sockPath)) return;
    // Try to connect — if it answers, another daemon is alive.
    const reachable = await new Promise<boolean>((resolve) => {
      const probe = net.createConnection(sockPath);
      let done = false;
      const finish = (v: boolean) => {
        if (done) return;
        done = true;
        try { probe.destroy(); } catch {}
        resolve(v);
      };
      probe.once('connect', () => finish(true));
      probe.once('error', () => finish(false));
      setTimeout(() => finish(false), 500);
    });
    if (reachable) {
      throw new Error('another daemon is already running at ' + sockPath);
    }
    try { unlinkSync(sockPath); } catch {}
  }

  // ─── per-connection ───────────────────────────────────────────────────────
  private acceptConn(socket: net.Socket): void {
    const id = randomUUID();
    const conn: Conn = {
      id,
      socket,
      decoder: new FrameDecoder(),
      token: null,
      name: null,
      roomCode: null,
    };
    this.conns.set(id, conn);
    socket.on('data', (chunk) => this.onData(conn, chunk));
    socket.on('close', () => this.onClose(conn));
    socket.on('error', () => this.onClose(conn));
  }

  private onData(conn: Conn, chunk: Buffer): void {
    let msgs: (C2S | S2C)[];
    try {
      msgs = conn.decoder.push(chunk);
    } catch (e) {
      if (e instanceof ProtocolError) {
        this.sendRaw(conn, { v: 1, t: 'ERROR', code: e.code, message: e.message });
        return;
      }
      throw e;
    }
    for (const m of msgs) {
      this.handle(conn, m as C2S);
    }
  }

  private onClose(conn: Conn): void {
    if (!this.conns.has(conn.id)) return;
    this.conns.delete(conn.id);
    if (conn.roomCode) {
      const room = this.rooms.get(conn.roomCode);
      if (room) {
        const seat = room.seatByConnId(conn.id);
        if (seat !== -1) room.detach(seat);
        if (!room.hasAnyHumans()) {
          this.rooms.delete(conn.roomCode);
        }
      }
    }
  }

  // ─── routing ──────────────────────────────────────────────────────────────
  private handle(conn: Conn, msg: C2S): void {
    try {
      switch (msg.t) {
        case 'HELLO': return this.onHello(conn, msg);
        case 'CREATE_ROOM': return this.onCreateRoom(conn);
        case 'JOIN_ROOM': return this.onJoinRoom(conn, msg.code);
        case 'ADD_AI_SEAT': return this.withRoom(conn, (room) =>
          room.addAiSeat(conn.id, msg.discipline));
        case 'REMOVE_SEAT': return this.withRoom(conn, (room) =>
          room.removeSeat(conn.id, msg.seat));
        case 'READY': return this.withRoom(conn, (room) =>
          room.setReady(conn.id, msg.ready));
        case 'START': return this.withRoom(conn, (room) => room.start(conn.id));
        case 'ACTION': return this.withRoom(conn, (room) =>
          room.submitAction(conn.id, msg.action));
        case 'LEAVE': return this.onLeave(conn);
      }
    } catch (e) {
      if (e instanceof RoomError || e instanceof ProtocolError) {
        this.sendRaw(conn, { v: 1, t: 'ERROR', code: e.code, message: e.message });
        return;
      }
      throw e;
    }
  }

  private onHello(conn: Conn, msg: Extract<C2S, { t: 'HELLO' }>): void {
    conn.name = msg.name;
    conn.token = msg.token ?? null;

    // If the token matches a known seat in any room, attach.
    if (msg.token) {
      for (const [code, room] of this.rooms) {
        const seatIdx = room.seats.findIndex(
          (s) => s.kindBase === 'human' && s.token === msg.token,
        );
        if (seatIdx !== -1) {
          // Detach the old socket if any (room handles emitting BYE).
          const old = room.seats[seatIdx].connId;
          if (old && old !== conn.id) {
            const oldConn = this.conns.get(old);
            if (oldConn) {
              oldConn.roomCode = null;
            }
          }
          const r = room.joinHuman(msg.name, conn.id, msg.token);
          conn.token = r.token;
          conn.roomCode = code;
          this.sendRaw(conn, {
            v: 1, t: 'WELCOME', token: r.token,
            seatHint: { code, seat: r.seat },
          });
          return;
        }
      }
    }
    // No matching seat: just mint/echo a token; client will create or join.
    const token = msg.token ?? randomUUID();
    conn.token = token;
    this.sendRaw(conn, { v: 1, t: 'WELCOME', token });
  }

  private onCreateRoom(conn: Conn): void {
    if (!conn.name || !conn.token) throw new ProtocolError('NO_HELLO', 'HELLO first');
    if (conn.roomCode) throw new ProtocolError('ALREADY_IN_ROOM', 'already in room ' + conn.roomCode);
    const code = this.mintCode();
    const room = new Room(code, {
      rng: this.rng,
      now: this.now,
      bus: (e) => this.dispatch(e),
      mintToken: () => randomUUID(),
    });
    this.rooms.set(code, room);
    const r = room.joinHuman(conn.name, conn.id, conn.token);
    conn.token = r.token;
    conn.roomCode = code;
  }

  private onJoinRoom(conn: Conn, code: string): void {
    if (!conn.name || !conn.token) throw new ProtocolError('NO_HELLO', 'HELLO first');
    if (conn.roomCode) throw new ProtocolError('ALREADY_IN_ROOM', 'already in room ' + conn.roomCode);
    const room = this.rooms.get(code);
    if (!room) throw new RoomError('NO_ROOM', 'room not found');
    const r = room.joinHuman(conn.name, conn.id, conn.token);
    conn.token = r.token;
    conn.roomCode = code;
  }

  private onLeave(conn: Conn): void {
    if (conn.roomCode) {
      const room = this.rooms.get(conn.roomCode);
      if (room) {
        const seat = room.seatByConnId(conn.id);
        if (seat !== -1) room.detach(seat);
        if (!room.hasAnyHumans()) this.rooms.delete(conn.roomCode);
      }
    }
    this.sendRaw(conn, { v: 1, t: 'BYE', reason: 'left' });
    conn.socket.end();
  }

  private withRoom(conn: Conn, fn: (room: Room) => void): void {
    if (!conn.roomCode) throw new ProtocolError('NO_ROOM', 'not in a room');
    const room = this.rooms.get(conn.roomCode);
    if (!room) throw new RoomError('NO_ROOM', 'room vanished');
    fn(room);
  }

  // ─── tick / dispatch ──────────────────────────────────────────────────────
  private tickRooms(): void {
    const now = this.now();
    for (const [code, room] of [...this.rooms]) {
      room.tick(now);
      if (room.reaped) this.rooms.delete(code);
    }
  }

  private dispatch(e: RoomEvent): void {
    const conn = this.conns.get(e.connId);
    if (!conn) return;
    if (e.t === 'send') {
      this.sendRaw(conn, e.msg);
    } else {
      this.sendRaw(conn, { v: 1, t: 'BYE', reason: e.reason });
      conn.socket.end();
      this.conns.delete(conn.id);
    }
  }

  private sendRaw(conn: Conn, msg: S2C): void {
    try {
      conn.socket.write(encode(msg));
    } catch {
      // Socket likely closed; onClose will handle cleanup.
    }
  }

  // ─── room codes ───────────────────────────────────────────────────────────
  private mintCode(): string {
    for (let attempt = 0; attempt < 100; attempt++) {
      let code = '';
      for (let i = 0; i < CODE_LEN; i++) {
        code += CODE_CHARS[Math.floor(this.rng() * CODE_CHARS.length)];
      }
      if (!this.rooms.has(code)) return code;
    }
    throw new Error('could not mint a unique room code');
  }
}

async function main(): Promise<void> {
  const daemon = new Daemon();
  await daemon.listen();
  const shutdown = async (sig: string) => {
    console.log(JSON.stringify({ ts: Date.now(), level: 'info', msg: 'shutdown', sig }));
    await daemon.close();
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

const isEntry = process.argv[1] && import.meta.url === 'file://' + process.argv[1];
if (isEntry) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
