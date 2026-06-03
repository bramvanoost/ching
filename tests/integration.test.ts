// Two-client end-to-end through the daemon. Boots the daemon on a temp
// socket with a seeded RNG, opens two raw socket clients, plays a full
// game using decide() as the action source, and asserts both clients
// receive matching final state.

import * as net from 'node:net';
import { describe, expect, it } from 'vitest';
import { tmpdir } from 'node:os';
import { join as pathJoin } from 'node:path';
import { Daemon } from '../src/net/daemon.js';
import { FrameDecoder, encode, type C2S, type S2C } from '../src/net/protocol.js';
import { decide } from '../src/ai.js';
import type { Action, Rng } from '../src/engine.js';

function mulberry32(seed: number): Rng {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

type Client = {
  socket: net.Socket;
  send: (m: C2S) => void;
  next: () => Promise<S2C>;
  inbox: S2C[];
  close: () => void;
};

type Target = string | { host: string; port: number };

function openClient(target: Target): Promise<Client> {
  return new Promise((resolve, reject) => {
    const socket = typeof target === 'string'
      ? net.createConnection(target)
      : net.createConnection(target.port, target.host);
    const decoder = new FrameDecoder();
    const inbox: S2C[] = [];
    const waiters: Array<(m: S2C) => void> = [];
    socket.once('connect', () => {
      socket.on('data', (chunk) => {
        for (const m of decoder.push(chunk)) {
          const sm = m as S2C;
          if (waiters.length > 0) waiters.shift()!(sm);
          else inbox.push(sm);
        }
      });
      socket.on('error', () => {});
      resolve({
        socket,
        inbox,
        send: (m: C2S) => socket.write(encode(m)),
        next: () => {
          if (inbox.length > 0) return Promise.resolve(inbox.shift()!);
          return new Promise<S2C>((r) => waiters.push(r));
        },
        close: () => socket.end(),
      });
    });
    socket.once('error', reject);
  });
}

async function nextMatching(c: Client, pred: (m: S2C) => boolean): Promise<S2C> {
  for (;;) {
    const m = await c.next();
    if (pred(m)) return m;
  }
}

async function playFullGameVia(target: Target): Promise<void> {
  const a = await openClient(target);
  const b = await openClient(target);

  a.send({ v: 1, t: 'HELLO', name: 'alice' });
  b.send({ v: 1, t: 'HELLO', name: 'bob' });
  await nextMatching(a, (m) => m.t === 'WELCOME');
  await nextMatching(b, (m) => m.t === 'WELCOME');

  a.send({ v: 1, t: 'CREATE_ROOM' });
  const aRoom = (await nextMatching(a, (m) => m.t === 'ROOM_STATE')) as Extract<S2C, { t: 'ROOM_STATE' }>;
  const code = aRoom.code;

  b.send({ v: 1, t: 'JOIN_ROOM', code });
  await nextMatching(a, (m) => m.t === 'ROOM_STATE' && m.seats.length === 2);
  await nextMatching(b, (m) => m.t === 'ROOM_STATE' && m.seats.length === 2);

  a.send({ v: 1, t: 'READY', ready: true });
  b.send({ v: 1, t: 'READY', ready: true });
  await nextMatching(a, (m) => m.t === 'ROOM_STATE' && m.seats.every((s) => s.ready));

  a.send({ v: 1, t: 'START' });

  // Play loop: read GAME_STATE pushes, whoever is current sends ACTION
  // chosen by decide() with discipline 0.6.
  const difficulty = { discipline: 0.6 };
  let aLastState = null as null | Extract<S2C, { t: 'GAME_STATE' }>;
  let bLastState = null as null | Extract<S2C, { t: 'GAME_STATE' }>;

  const seenOver = { a: false, b: false };
  const consume = async (cl: Client, who: 'a' | 'b') => {
    while (!seenOver[who]) {
      const m = await cl.next();
      if (m.t === 'GAME_STATE') {
        if (who === 'a') aLastState = m;
        else bLastState = m;
        if (m.state.phase === 'over') {
          seenOver[who] = true;
          break;
        }
      }
    }
  };
  const pumpA = consume(a, 'a');
  const pumpB = consume(b, 'b');

  const drive = async () => {
    let safety = 5_000;
    while (!seenOver.a && safety-- > 0) {
      const cur = (aLastState ?? bLastState);
      if (!cur) {
        await new Promise((r) => setTimeout(r, 5));
        continue;
      }
      if (cur.state.phase === 'over') break;
      const seat = cur.state.current;
      const action: Action = decide(cur.state, difficulty);
      const owner = seat === 0 ? a : b;
      const beforeSeat = cur.state.current;
      const beforeRolled = cur.state.rolled.length;
      const beforeSetAside = cur.state.setAside.length;
      owner.send({ v: 1, t: 'ACTION', action });
      const waitStart = Date.now();
      while (Date.now() - waitStart < 1000) {
        const latest = aLastState;
        if (
          latest &&
          (latest.state.current !== beforeSeat ||
            latest.state.rolled.length !== beforeRolled ||
            latest.state.setAside.length !== beforeSetAside ||
            latest.state.phase === 'over')
        ) {
          break;
        }
        await new Promise((r) => setTimeout(r, 2));
      }
    }
  };

  await drive();
  await pumpA;
  await pumpB;

  expect(aLastState).not.toBeNull();
  expect(bLastState).not.toBeNull();
  expect(aLastState!.state.phase).toBe('over');
  expect(bLastState!.state.phase).toBe('over');
  expect(aLastState!.state.players).toEqual(bLastState!.state.players);

  a.close();
  b.close();
}

describe('integration', () => {
  it('two clients play a full game over the unix socket', async () => {
    const sockPath = pathJoin(tmpdir(), 'ching-test-unix-' + process.pid + '-' + Date.now() + '.sock');
    const rng = mulberry32(42);
    const daemon = new Daemon({ rng, log: () => {} });
    await daemon.listen(sockPath);
    try {
      await playFullGameVia(sockPath);
    } finally {
      await daemon.close();
    }
  }, 20_000);

  it('two clients play a full game over TCP', async () => {
    // port: 0 asks the OS for any free port. host 127.0.0.1 keeps the test
    // bound to loopback so we never accidentally expose a CI runner to the
    // wider network. The production default is 0.0.0.0:4321.
    const sockPath = pathJoin(tmpdir(), 'ching-test-tcp-' + process.pid + '-' + Date.now() + '.sock');
    const rng = mulberry32(42);
    const daemon = new Daemon({ rng, log: () => {} });
    await daemon.listen({ sockPath, port: 0, host: '127.0.0.1' });
    expect(daemon.tcpPort).toBeGreaterThan(0);
    try {
      await playFullGameVia({ host: '127.0.0.1', port: daemon.tcpPort! });
    } finally {
      await daemon.close();
    }
  }, 20_000);

  it('drops a silent client after heartbeat timeout', async () => {
    // Two clients in a lobby; alice goes silent, bob keeps sending. After
    // we advance the daemon's clock past heartbeatTimeoutMs and tick,
    // alice's seat should appear disconnected to bob.
    const sockPath = pathJoin(tmpdir(), 'ching-test-hb-' + process.pid + '-' + Date.now() + '.sock');
    let mockNow = 1_000_000;
    const rng = mulberry32(11);
    const daemon = new Daemon({
      rng,
      now: () => mockNow,
      log: () => {},
      heartbeatTimeoutMs: 100,
      // tickMs is irrelevant: we drive tickRooms() manually below.
    });
    await daemon.listen(sockPath);
    try {
      const a = await openClient(sockPath);
      const b = await openClient(sockPath);

      a.send({ v: 1, t: 'HELLO', name: 'alice' });
      b.send({ v: 1, t: 'HELLO', name: 'bob' });
      await nextMatching(a, (m) => m.t === 'WELCOME');
      await nextMatching(b, (m) => m.t === 'WELCOME');

      a.send({ v: 1, t: 'CREATE_ROOM' });
      const aRoom = (await nextMatching(a, (m) => m.t === 'ROOM_STATE')) as Extract<S2C, { t: 'ROOM_STATE' }>;
      b.send({ v: 1, t: 'JOIN_ROOM', code: aRoom.code });
      await nextMatching(a, (m) => m.t === 'ROOM_STATE' && m.seats.length === 2);
      await nextMatching(b, (m) => m.t === 'ROOM_STATE' && m.seats.length === 2);

      // Jump the clock well past the timeout. Both seats look stale right
      // now; bob's PING below refreshes his lastActivityMs to the new now.
      mockNow += 500;
      b.send({ v: 1, t: 'PING' });
      // Yield to the event loop so the daemon receives and processes bob's
      // PING (updating his lastActivityMs) before we run the sweep.
      await new Promise((r) => setTimeout(r, 20));

      daemon.tickRooms();

      const drop = (await nextMatching(b, (m) =>
        m.t === 'ROOM_STATE' && m.seats.some((s) => s.name === 'alice' && !s.connected),
      )) as Extract<S2C, { t: 'ROOM_STATE' }>;
      const alice = drop.seats.find((s) => s.name === 'alice')!;
      const bob = drop.seats.find((s) => s.name === 'bob')!;
      expect(alice.connected).toBe(false);
      expect(bob.connected).toBe(true);

      a.close();
      b.close();
    } finally {
      await daemon.close();
    }
  }, 10_000);

  it('exposes both transports concurrently from one daemon', async () => {
    // Same daemon, one client over unix, one over TCP. Both should land in
    // the same room and see the same game state.
    const sockPath = pathJoin(tmpdir(), 'ching-test-both-' + process.pid + '-' + Date.now() + '.sock');
    const rng = mulberry32(7);
    const daemon = new Daemon({ rng, log: () => {} });
    await daemon.listen({ sockPath, port: 0, host: '127.0.0.1' });
    const port = daemon.tcpPort!;
    try {
      const a = await openClient(sockPath);
      const b = await openClient({ host: '127.0.0.1', port });

      a.send({ v: 1, t: 'HELLO', name: 'alice' });
      b.send({ v: 1, t: 'HELLO', name: 'bob' });
      await nextMatching(a, (m) => m.t === 'WELCOME');
      await nextMatching(b, (m) => m.t === 'WELCOME');

      a.send({ v: 1, t: 'CREATE_ROOM' });
      const aRoom = (await nextMatching(a, (m) => m.t === 'ROOM_STATE')) as Extract<S2C, { t: 'ROOM_STATE' }>;
      b.send({ v: 1, t: 'JOIN_ROOM', code: aRoom.code });
      const bRoom = (await nextMatching(b, (m) => m.t === 'ROOM_STATE' && m.seats.length === 2)) as Extract<S2C, { t: 'ROOM_STATE' }>;
      expect(bRoom.code).toBe(aRoom.code);
      expect(bRoom.seats.map((s) => s.name).sort()).toEqual(['alice', 'bob']);

      a.close();
      b.close();
    } finally {
      await daemon.close();
    }
  }, 10_000);
});
