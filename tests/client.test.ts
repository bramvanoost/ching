import { describe, expect, it, afterEach } from 'vitest';
import { tmpdir } from 'node:os';
import { join as pathJoin } from 'node:path';
import { readFileSync, rmSync } from 'node:fs';
import { reduce, initial } from '../src/clientcore.js';
import type { S2C } from '../src/net/protocol.js';
import { runClient, resolveSessionFile, loadSession, saveToken } from '../src/client.js';

describe('resolveSessionFile', () => {
  const prev = process.env.CHING_SESSION;
  afterEach(() => {
    if (prev === undefined) delete process.env.CHING_SESSION;
    else process.env.CHING_SESSION = prev;
  });

  it('honors CHING_SESSION', () => {
    process.env.CHING_SESSION = '/tmp/ching-test-override.json';
    expect(resolveSessionFile()).toBe('/tmp/ching-test-override.json');
  });

  it('falls back to ~/.ching/session.json when CHING_SESSION is unset', () => {
    delete process.env.CHING_SESSION;
    expect(resolveSessionFile()).toMatch(/\.ching\/session\.json$/);
  });
});

describe('session token file', () => {
  const file = pathJoin(tmpdir(), 'ching-test-session-' + process.pid + '.json');
  afterEach(() => {
    try { rmSync(file); } catch {}
  });

  it('keys tokens by socket path within one file', () => {
    saveToken(file, '/tmp/sock-a.sock', 'tok-A');
    saveToken(file, '/tmp/sock-b.sock', 'tok-B');
    expect(loadSession(file, '/tmp/sock-a.sock').token).toBe('tok-A');
    expect(loadSession(file, '/tmp/sock-b.sock').token).toBe('tok-B');
  });

  it('two separate session files hold independent tokens for the same socket', () => {
    const fileA = file + '.A';
    const fileB = file + '.B';
    try {
      saveToken(fileA, '/tmp/ching.sock', 'tok-alice');
      saveToken(fileB, '/tmp/ching.sock', 'tok-bob');
      expect(loadSession(fileA, '/tmp/ching.sock').token).toBe('tok-alice');
      expect(loadSession(fileB, '/tmp/ching.sock').token).toBe('tok-bob');
      // Sanity: file A still has its token unchanged after writing file B.
      const rawA = JSON.parse(readFileSync(fileA, 'utf8')) as Record<string, { token: string }>;
      expect(rawA['/tmp/ching.sock'].token).toBe('tok-alice');
    } finally {
      try { rmSync(fileA); } catch {}
      try { rmSync(fileB); } catch {}
    }
  });
});

describe('clientcore reducer', () => {
  it('persists token on WELCOME', () => {
    const s0 = initial('alice', null);
    const r = reduce(s0, { v: 1, t: 'WELCOME', token: 'tok-1' });
    expect(r.next.token).toBe('tok-1');
    expect(r.side).toContainEqual({ t: 'persist-token', token: 'tok-1' });
  });

  it('moves to lobby phase on ROOM_STATE { phase: lobby }', () => {
    let s = initial('alice', null);
    s = reduce(s, { v: 1, t: 'WELCOME', token: 'tok-1' }).next;
    const r = reduce(s, {
      v: 1, t: 'ROOM_STATE', code: 'X7K3', host: 0, phase: 'lobby',
      seats: [
        { seat: 0, name: 'alice', kind: 'human', ready: false, connected: true },
        { seat: 1, name: 'bob', kind: 'human', ready: false, connected: true },
      ],
    });
    expect(r.next.phase.kind).toBe('lobby');
  });

  it('stores TURN_REMINDER on the reducer state', () => {
    let s = initial('alice', null);
    s = reduce(s, { v: 1, t: 'WELCOME', token: 'tok-1' }).next;
    const r = reduce(s, { v: 1, t: 'TURN_REMINDER', seat: 1, secondsLeft: 10 });
    expect(r.next.reminder).toEqual({ seat: 1, secondsLeft: 10 });
  });

  it('emits teardown on BYE', () => {
    const s = initial('alice', 'tok-1');
    const r = reduce(s, { v: 1, t: 'BYE', reason: 'replaced' });
    expect(r.side).toContainEqual({ t: 'teardown', exitCode: 0 });
  });
});

// ─── runClient terminal teardown invariant ──────────────────────────────────
type SentMsg = { v: 1; t: string; [k: string]: unknown };

function fakeConn() {
  const sent: SentMsg[] = [];
  let onMsg: ((m: S2C) => void) | null = null;
  let onClose: (() => void) | null = null;
  return {
    sent,
    inject(m: S2C) { onMsg?.(m); },
    triggerClose() { onClose?.(); },
    conn: {
      send: (m: SentMsg) => { sent.push(m); },
      onMessage: (h: (m: S2C) => void) => { onMsg = h; },
      onClose: (h: () => void) => { onClose = h; },
      close: () => { /* no-op */ },
    },
  };
}

function fakeTerm() {
  const events: string[] = [];
  let pendingKey: ((k: string) => void) | null = null;
  return {
    events,
    deliverKey(k: string) {
      const p = pendingKey;
      pendingKey = null;
      p?.(k);
    },
    term: {
      setup: () => { events.push('setup'); },
      teardown: () => { events.push('teardown'); },
      draw: (_s: string) => { events.push('draw'); },
      showCursor: () => { events.push('show'); },
      hideCursor: () => { events.push('hide'); },
      waitKey: () => new Promise<string>((r) => { pendingKey = r; }),
      delay: (_ms: number) => Promise.resolve(),
    },
  };
}

describe('runClient teardown invariant', () => {
  it('calls term.teardown() on BYE { reason: "replaced" }', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      sockPath: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json', name: 'alice', token: 'tok-1',
    });
    // Give the message loop a tick to start.
    await Promise.resolve();
    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    const code = await runPromise;
    expect(t.events).toContain('setup');
    expect(t.events).toContain('teardown');
    expect(code).toBe(0);
  });

  it('calls term.teardown() on BYE { reason: "server shutting down" }', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      sockPath: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json', name: 'alice', token: null,
    });
    await Promise.resolve();
    c.inject({ v: 1, t: 'BYE', reason: 'server shutting down' });
    const code = await runPromise;
    expect(t.events).toContain('teardown');
    expect(code).toBe(0);
  });

  it('calls term.teardown() on abrupt socket close with no BYE', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      sockPath: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json', name: 'alice', token: null,
    });
    await Promise.resolve();
    c.triggerClose();
    const code = await runPromise;
    expect(t.events).toContain('teardown');
    expect(code).toBe(1);
  });
});
