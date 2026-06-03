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
import { makeDefaultLog, type LogFn } from './log.js';

export const DEFAULT_SOCK = '/tmp/ching.sock';
export const DEFAULT_PORT = 4321;
export const DEFAULT_HOST = '0.0.0.0';
// Heartbeat defaults. Client sends PING every 5s; daemon drops the conn if
// it hasn't heard anything for 10s. Two consecutive missed pings = drop.
export const DEFAULT_HEARTBEAT_TIMEOUT_MS = 10_000;

// Excludes ambiguous chars (0,1,I,L,O) AND every reserved single-key hotkey
// (A add-AI, C create, J join, K kick, L leave, Q quit, R ready/roll, S start/stop)
// so a room code can never collide with the global hotkey set. 16 letters +
// 8 digits = 24 chars; 24^4 = 331,776 codes, plenty for a 4-char space.
export const CODE_CHARS = 'BDEFGHMNPTUVWXYZ23456789';
const CODE_LEN = 4;
const DEFAULT_TICK_MS = 1_000;

// listen() accepts either a legacy string (the unix socket path; TCP stays
// off) or this opts object. main() uses the opts form to enable both.
export type ListenOpts = {
  sockPath?: string | null;  // unix socket path; null disables unix transport
  port?: number | null;      // TCP port; null disables TCP transport
  host?: string;             // TCP bind host, defaults to 0.0.0.0
};

type Conn = {
  id: string;
  socket: net.Socket;
  decoder: FrameDecoder;
  token: string | null;
  name: string | null;
  roomCode: string | null;
  // Wall-clock timestamp (from deps.now) of the last byte we received on
  // this conn. The heartbeat check in tickRooms drops conns that have gone
  // silent for longer than heartbeatTimeoutMs. Without this, a killed
  // client (closed laptop, dropped wifi) wouldn't emit 'close' and its
  // seat would appear connected forever to other players.
  lastActivityMs: number;
};

export type DaemonDeps = {
  rng?: Rng;
  now?: () => number;
  log?: LogFn;
  heartbeatTimeoutMs?: number;
  tickMs?: number;
};

export class Daemon {
  private rooms = new Map<string, Room>();
  private conns = new Map<string, Conn>();
  private tickHandle: NodeJS.Timeout | null = null;
  private unixServer: net.Server | null = null;
  private tcpServer: net.Server | null = null;
  // Populated by listen() if a TCP server is started. Useful for tests that
  // ask the OS for a port (port: 0) and need to know which one was assigned.
  tcpPort: number | null = null;
  private readonly rng: Rng;
  private readonly now: () => number;
  private readonly log: LogFn;
  private readonly heartbeatTimeoutMs: number;
  private readonly tickMs: number;

  constructor(deps: DaemonDeps = {}) {
    this.rng = deps.rng ?? Math.random;
    this.now = deps.now ?? Date.now;
    this.log = deps.log ?? makeDefaultLog(this.now);
    this.heartbeatTimeoutMs = deps.heartbeatTimeoutMs ?? DEFAULT_HEARTBEAT_TIMEOUT_MS;
    this.tickMs = deps.tickMs ?? DEFAULT_TICK_MS;
  }

  // ─── lifecycle ────────────────────────────────────────────────────────────
  // Accepts a string (legacy: unix socket only, TCP stays off) OR an opts
  // object that can enable TCP, unix, or both. The room/daemon logic is
  // transport-agnostic: acceptConn just takes a net.Socket.
  async listen(target: string | ListenOpts = DEFAULT_SOCK): Promise<void> {
    const opts: ListenOpts = typeof target === 'string'
      ? { sockPath: target, port: null }
      : target;
    const sockPath = opts.sockPath === undefined ? DEFAULT_SOCK : opts.sockPath;
    const port = opts.port === undefined ? null : opts.port;
    const host = opts.host ?? DEFAULT_HOST;

    if (sockPath === null && port === null) {
      throw new Error('Daemon.listen requires sockPath, port, or both');
    }

    if (sockPath !== null) await this.startUnix(sockPath);
    if (port !== null) await this.startTcp(host, port);

    this.tickHandle = setInterval(() => this.tickRooms(), this.tickMs);
  }

  private async startUnix(sockPath: string): Promise<void> {
    await this.cleanStaleSocket(sockPath);
    await new Promise<void>((resolve, reject) => {
      const server = net.createServer((socket) => this.acceptConn(socket));
      server.on('error', reject);
      server.listen(sockPath, () => {
        try { chmodSync(sockPath, 0o660); } catch {}
        this.unixServer = server;
        resolve();
      });
    });
    this.log({ level: 'info', msg: 'listening', transport: 'unix', sock: sockPath });
  }

  private async startTcp(host: string, port: number): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      const server = net.createServer((socket) => this.acceptConn(socket));
      server.on('error', reject);
      server.listen(port, host, () => {
        const addr = server.address();
        if (addr && typeof addr === 'object') this.tcpPort = addr.port;
        else this.tcpPort = port;
        this.tcpServer = server;
        resolve();
      });
    });
    this.log({
      level: 'info', msg: 'listening', transport: 'tcp',
      host, port: this.tcpPort ?? port,
    });
  }

  async close(reason = 'server shutting down'): Promise<void> {
    if (this.tickHandle) {
      clearInterval(this.tickHandle);
      this.tickHandle = null;
    }
    this.log({ level: 'info', msg: 'shutdown', reason });
    for (const c of this.conns.values()) {
      this.sendRaw(c, { v: 1, t: 'BYE', reason });
      c.socket.end();
    }
    const closers: Promise<void>[] = [];
    if (this.unixServer) {
      const s = this.unixServer;
      closers.push(new Promise<void>((r) => s.close(() => r())));
      this.unixServer = null;
    }
    if (this.tcpServer) {
      const s = this.tcpServer;
      closers.push(new Promise<void>((r) => s.close(() => r())));
      this.tcpServer = null;
    }
    this.tcpPort = null;
    await Promise.all(closers);
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
    // Enable OS-level TCP keepalive on the accepted socket. The second arg is
    // the idle time before the first probe. No-op on unix sockets (the call
    // either silently ignores or errors, which we swallow). This is a backup
    // to the app-level heartbeat: app heartbeat catches most silent drops
    // first, keepalive handles the OS-stack-stuck cases.
    try {
      socket.setKeepAlive(true, this.heartbeatTimeoutMs);
    } catch {}
    const conn: Conn = {
      id,
      socket,
      decoder: new FrameDecoder(),
      token: null,
      name: null,
      roomCode: null,
      lastActivityMs: this.now(),
    };
    this.conns.set(id, conn);
    this.log({ level: 'debug', msg: 'connect', conn: id.slice(0, 8) });
    socket.on('data', (chunk) => this.onData(conn, chunk));
    socket.on('close', () => this.onClose(conn));
    socket.on('error', () => this.onClose(conn));
  }

  private onData(conn: Conn, chunk: Buffer): void {
    // Any byte resets the activity clock. PING, ACTION, READY, all the same.
    conn.lastActivityMs = this.now();
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
    this.dropConn(conn, 'close');
  }

  // Shared by 'close'/'error' events and by the heartbeat-timeout sweep.
  // Idempotent — calling it twice (e.g. heartbeat first, then 'close' from
  // the destroyed socket) is a no-op the second time.
  private dropConn(conn: Conn, reason: 'close' | 'heartbeat'): void {
    if (!this.conns.has(conn.id)) return;
    this.conns.delete(conn.id);
    this.log({
      level: 'debug',
      msg: 'disconnect',
      conn: conn.id.slice(0, 8),
      reason,
      ...(conn.roomCode ? { room: conn.roomCode } : {}),
      ...(conn.name ? { name: conn.name } : {}),
    });
    if (conn.roomCode) {
      const room = this.rooms.get(conn.roomCode);
      if (room) {
        const seat = room.seatByConnId(conn.id);
        // detach() pushes ROOM_STATE (lobby) or GAME_STATE (playing) to all
        // remaining live conns with connected:false for this seat, and if
        // the dropped seat is currently active, starts the 15s grace timer
        // which immediately emits TURN_REMINDER(secondsLeft=15) to everyone
        // else.
        if (seat !== -1) room.detach(seat);
        if (!room.hasAnyHumans()) {
          this.rooms.delete(conn.roomCode);
          this.log({ level: 'info', msg: 'room_closed', room: conn.roomCode, reason: 'no_humans' });
        }
      }
    }
    if (reason === 'heartbeat') {
      // Force-close the underlying socket so the OS releases it. 'close'
      // will fire later; dropConn is idempotent so that's fine.
      try { conn.socket.destroy(); } catch {}
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
        case 'PING': return; // activity already recorded in onData
      }
    } catch (e) {
      if (e instanceof RoomError || e instanceof ProtocolError) {
        this.log({
          level: 'info', msg: 'error', code: e.code,
          err: e.message, ...(conn.roomCode ? { room: conn.roomCode } : {}),
        });
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
          this.log({
            level: 'info', msg: 'HELLO', room: code, seat: r.seat,
            name: msg.name, kind: 'reclaim',
          });
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
    this.log({ level: 'info', msg: 'HELLO', name: msg.name, kind: msg.token ? 'rehello' : 'new' });
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
      log: this.log,
    });
    this.rooms.set(code, room);
    const r = room.joinHuman(conn.name, conn.id, conn.token);
    conn.token = r.token;
    conn.roomCode = code;
    this.log({ level: 'info', msg: 'CREATE_ROOM', room: code, seat: r.seat, name: conn.name });
  }

  private onJoinRoom(conn: Conn, code: string): void {
    if (!conn.name || !conn.token) throw new ProtocolError('NO_HELLO', 'HELLO first');
    if (conn.roomCode) throw new ProtocolError('ALREADY_IN_ROOM', 'already in room ' + conn.roomCode);
    const room = this.rooms.get(code);
    if (!room) throw new RoomError('NO_ROOM', 'room not found');
    const r = room.joinHuman(conn.name, conn.id, conn.token);
    conn.token = r.token;
    conn.roomCode = code;
    this.log({ level: 'info', msg: 'JOIN_ROOM', room: code, seat: r.seat, name: conn.name });
  }

  private onLeave(conn: Conn): void {
    if (conn.roomCode) {
      const room = this.rooms.get(conn.roomCode);
      if (room) {
        // Intentional departure: room.leave converts the seat to a permanent
        // AI (mid-game) or splices it out (lobby). Distinct from detach,
        // which is the path a silent socket-close takes and which keeps
        // the seat reservable for grace + reclaim.
        room.leave(conn.id);
        if (!room.hasAnyHumans()) {
          this.rooms.delete(conn.roomCode);
          this.log({ level: 'info', msg: 'room_closed', room: conn.roomCode, reason: 'last_left' });
        }
      }
      this.log({ level: 'info', msg: 'LEAVE', room: conn.roomCode, name: conn.name ?? undefined });
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
  // Test hook: invoked by tickHandle but also callable by integration tests.
  tickRooms(): void {
    const now = this.now();

    // Heartbeat sweep: any conn that hasn't sent a byte (including PING) in
    // heartbeatTimeoutMs is presumed silently dropped. A killed / suspended
    // client or a dropped wifi link often never emits 'close', so without
    // this its seat appears connected forever to other players.
    for (const conn of [...this.conns.values()]) {
      const idleMs = now - conn.lastActivityMs;
      if (idleMs >= this.heartbeatTimeoutMs) {
        this.log({
          level: 'info', msg: 'heartbeat_timeout',
          conn: conn.id.slice(0, 8), idle_ms: idleMs,
          ...(conn.roomCode ? { room: conn.roomCode } : {}),
          ...(conn.name ? { name: conn.name } : {}),
        });
        this.dropConn(conn, 'heartbeat');
      }
    }

    for (const [code, room] of [...this.rooms]) {
      room.tick(now);
      if (room.reaped) {
        this.rooms.delete(code);
        this.log({ level: 'info', msg: 'reaped', room: code });
      }
    }
  }

  private dispatch(e: RoomEvent): void {
    const conn = this.conns.get(e.connId);
    if (!conn) return;
    if (e.t === 'send') {
      this.sendRaw(conn, e.msg);
    } else {
      this.log({
        level: 'info', msg: 'BYE', reason: e.reason,
        ...(conn.roomCode ? { room: conn.roomCode } : {}),
        ...(conn.name ? { name: conn.name } : {}),
      });
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
  // Listen on BOTH transports by default: unix for local players (no auth
  // setup needed) and TCP for LAN peers (set CHING_HOST=<ip> on the client).
  // CHING_PORT=0 disables the TCP listener; any other parses as a port.
  const portEnv = process.env.CHING_PORT;
  const port = portEnv === undefined ? DEFAULT_PORT : Number(portEnv);
  await daemon.listen({
    sockPath: process.env.CHING_SOCK ?? DEFAULT_SOCK,
    port: Number.isFinite(port) && port > 0 ? port : null,
    host: process.env.CHING_BIND ?? DEFAULT_HOST,
  });
  const shutdown = async (_sig: string) => {
    // daemon.close already logs the shutdown event with its reason.
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
