import { describe, expect, it, afterEach } from 'vitest';
import { tmpdir } from 'node:os';
import { join as pathJoin } from 'node:path';
import { writeFileSync, rmSync } from 'node:fs';
import { reduce, initial } from '../src/clientcore.js';
import type { S2C } from '../src/net/protocol.js';
import {
  runClient,
  resolveSessionFile,
  loadSession,
  saveToken,
  loadProfile,
  saveProfile,
  parseHost,
  pickConnection,
  readCode,
  readSeatNumber,
} from '../src/client.js';
import { CODE_CHARS as DAEMON_CODE_CHARS } from '../src/net/daemon.js';

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
      // Sanity: writing file B left file A's token untouched.
      expect(loadSession(fileA, '/tmp/ching.sock').token).toBe('tok-alice');
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
  const draws: string[] = [];
  const queue: string[] = [];
  const waiters: Array<(k: string) => void> = [];
  return {
    events,
    draws,
    deliverKey(k: string) {
      const w = waiters.shift();
      if (w) w(k);
      else queue.push(k);
    },
    term: {
      setup: () => { events.push('setup'); },
      teardown: () => { events.push('teardown'); },
      draw: (s: string) => { events.push('draw'); draws.push(s); },
      drawFooter: (s: string) => { events.push('drawFooter'); draws.push(s); return true; },
      showCursor: () => { events.push('show'); },
      hideCursor: () => { events.push('hide'); },
      waitKey: () => {
        if (queue.length > 0) return Promise.resolve(queue.shift()!);
        return new Promise<string>((r) => waiters.push(r));
      },
      delay: (_ms: number) => Promise.resolve(),
    },
  };
}

// Pump enough microtasks for runClient's input loop + message loop to drain
// after each external stimulus. Two awaits is enough in practice because the
// loops are single-await-per-step.
async function pump(): Promise<void> {
  for (let i = 0; i < 4; i++) await Promise.resolve();
}

describe('runClient teardown invariant', () => {
  it('calls term.teardown() on BYE { reason: "replaced" }', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json', name: 'alice', token: 'tok-1',
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
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json', name: 'alice', token: null,
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
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json', name: 'alice', token: null,
    });
    await Promise.resolve();
    c.triggerClose();
    const code = await runPromise;
    expect(t.events).toContain('teardown');
    expect(code).toBe(1);
  });
});

// ─── modal input: readCode / readSeatNumber ─────────────────────────────────
function makeModalTerm() {
  const drawn: string[] = [];
  const queue: string[] = [];
  const waiters: Array<(k: string) => void> = [];
  return {
    drawn,
    feed(k: string) {
      const w = waiters.shift();
      if (w) w(k);
      else queue.push(k);
    },
    term: {
      setup: () => {},
      teardown: () => {},
      draw: (s: string) => { drawn.push(s); },
      showCursor: () => {},
      hideCursor: () => {},
      waitKey: () => {
        if (queue.length > 0) return Promise.resolve(queue.shift()!);
        return new Promise<string>((r) => waiters.push(r));
      },
      delay: (_ms: number) => Promise.resolve(),
    },
  };
}

describe('readCode modal', () => {
  it('types former-hotkey letters into the field', async () => {
    const ft = makeModalTerm();
    // Q, R, A, S were all global hotkeys; they must now type into the field.
    for (const k of ['Q', 'R', 'A', 'S']) ft.feed(k);
    const code = await readCode(ft.term as never);
    expect(code).toBe('QRAS');
  });

  it('accepts a mixed-case code (lowercase typed is uppercased)', async () => {
    const ft = makeModalTerm();
    // c, j, k, s are former hotkeys (now safe to type). L is excluded as
    // ambiguous (matches 1/I) regardless of hotkey status.
    for (const k of ['c', 'j', 'k', 's']) ft.feed(k);
    const code = await readCode(ft.term as never);
    expect(code).toBe('CJKS');
  });

  it('treats ESC as the only cancel', async () => {
    const ft = makeModalTerm();
    ft.feed('Q'); // would have cancelled in old code
    ft.feed('R');
    ft.feed('\x1b'); // ESC: real cancel
    const code = await readCode(ft.term as never);
    expect(code).toBeNull();
  });

  it('hides the cursor on cancel (try/finally invariant)', async () => {
    const ft = makeModalTerm();
    ft.feed('\x1b');
    await readCode(ft.term as never);
    expect(ft.drawn.some((s) => s.endsWith('?25l'))).toBe(true);
  });

  it('hides the cursor on accept', async () => {
    const ft = makeModalTerm();
    for (const k of ['B', 'D', 'E', 'F']) ft.feed(k);
    await readCode(ft.term as never);
    expect(ft.drawn.some((s) => s.endsWith('?25l'))).toBe(true);
  });

  it('supports backspace', async () => {
    const ft = makeModalTerm();
    ft.feed('Q');
    ft.feed('R');
    ft.feed('\x7f'); // backspace
    ft.feed('A');
    ft.feed('S');
    ft.feed('\r'); // Enter accepts, but length 3 → returns null
    const code = await readCode(ft.term as never);
    expect(code).toBeNull();
  });

  it('drops multi-char escape sequences (arrow keys) without crashing', async () => {
    const ft = makeModalTerm();
    ft.feed('\x1b[A'); // up-arrow: starts with ESC but is not a lone ESC
    ft.feed('\x1b[B'); // down-arrow
    ft.feed('B');
    ft.feed('D');
    ft.feed('E');
    ft.feed('F');
    const code = await readCode(ft.term as never);
    expect(code).toBe('BDEF');
  });

  it('ignores unknown / out-of-alphabet input without crashing', async () => {
    const ft = makeModalTerm();
    ft.feed('!');
    ft.feed('@');
    ft.feed('0'); // excluded ambiguous char
    ft.feed('1'); // excluded ambiguous char
    ft.feed('I'); // excluded ambiguous char
    ft.feed('B');
    ft.feed('D');
    ft.feed('E');
    ft.feed('F');
    const code = await readCode(ft.term as never);
    expect(code).toBe('BDEF');
  });

  it('returns null cleanly if waitKey rejects', async () => {
    const term = {
      draw: () => {},
      waitKey: () => Promise.reject(new Error('stdin closed')),
    };
    const code = await readCode(term as never);
    expect(code).toBeNull();
  });
});

describe('readSeatNumber modal', () => {
  it('returns seat - 1 for a valid digit', async () => {
    const ft = makeModalTerm();
    ft.feed('2');
    const seat = await readSeatNumber(ft.term as never, 4);
    expect(seat).toBe(1);
  });

  it('returns null for ESC', async () => {
    const ft = makeModalTerm();
    ft.feed('\x1b');
    const seat = await readSeatNumber(ft.term as never, 4);
    expect(seat).toBeNull();
  });

  it('returns null for letters (former hotkeys do not throw)', async () => {
    for (const k of ['Q', 'R', 'A', 'S', 'L', 'K']) {
      const ft = makeModalTerm();
      ft.feed(k);
      const seat = await readSeatNumber(ft.term as never, 4);
      expect(seat).toBeNull();
    }
  });

  it('returns null for out-of-range digits', async () => {
    const ft = makeModalTerm();
    ft.feed('9');
    const seat = await readSeatNumber(ft.term as never, 4);
    expect(seat).toBeNull();
  });
});

// ─── daemon code alphabet ───────────────────────────────────────────────────
describe('daemon code alphabet', () => {
  it('excludes every reserved global hotkey letter', () => {
    // A=add AI, C=create, J=join, K=kick, L=leave, Q=quit, R=ready/roll, S=start/stop
    for (const c of 'ACJKLQRS') {
      expect(DAEMON_CODE_CHARS).not.toContain(c);
    }
  });

  it('excludes ambiguous characters', () => {
    for (const c of '01ILO') {
      expect(DAEMON_CODE_CHARS).not.toContain(c);
    }
  });

  it('leaves enough entropy for 4-char codes', () => {
    // 16 letters + 8 digits = 24 chars → 24^4 = 331,776 codes.
    expect(DAEMON_CODE_CHARS.length).toBeGreaterThanOrEqual(20);
  });

  it('every character in the alphabet is safe (sweep)', () => {
    const reserved = new Set('ACJKLQRS01ILO'.split(''));
    for (const ch of DAEMON_CODE_CHARS) {
      expect(reserved.has(ch)).toBe(false);
    }
  });
});

// ─── Profile schema + legacy compat ─────────────────────────────────────────
describe('Profile persistence', () => {
  const file = pathJoin(tmpdir(), 'ching-test-profile-' + process.pid + '.json');
  afterEach(() => { try { rmSync(file); } catch {} });

  it('round-trips name, lastHost, and tokens', () => {
    saveProfile(file, {
      name: 'alice',
      lastHost: 'tcp://192.168.1.42:4321',
      tokens: { '/tmp/ching.sock': { token: 'tok-1' } },
    });
    const p = loadProfile(file);
    expect(p.name).toBe('alice');
    expect(p.lastHost).toBe('tcp://192.168.1.42:4321');
    expect(p.tokens?.['/tmp/ching.sock']?.token).toBe('tok-1');
  });

  it('reads legacy flat {target: {token}} files and exposes them under tokens', () => {
    // Pre-Profile-schema layout that an existing user might have on disk.
    writeFileSync(file, JSON.stringify({
      '/tmp/ching.sock': { token: 'tok-legacy' },
      'tcp://10.0.0.1:4321': { token: 'tok-legacy-tcp' },
    }, null, 2));
    const p = loadProfile(file);
    expect(p.tokens?.['/tmp/ching.sock']?.token).toBe('tok-legacy');
    expect(p.tokens?.['tcp://10.0.0.1:4321']?.token).toBe('tok-legacy-tcp');
    expect(p.name).toBeUndefined();
    expect(p.lastHost).toBeUndefined();
  });

  it('saveToken on a legacy file migrates it to the new shape on next read', () => {
    writeFileSync(file, JSON.stringify({
      '/tmp/ching.sock': { token: 'tok-old' },
    }, null, 2));
    saveToken(file, '/tmp/ching.sock', 'tok-new');
    const p = loadProfile(file);
    expect(p.tokens?.['/tmp/ching.sock']?.token).toBe('tok-new');
  });

  it('returns an empty profile if the file does not exist', () => {
    const missing = pathJoin(tmpdir(), 'ching-no-such-file-' + Date.now() + '.json');
    expect(loadProfile(missing)).toEqual({});
  });

  it('returns an empty profile if the file is malformed', () => {
    writeFileSync(file, 'not json');
    expect(loadProfile(file)).toEqual({});
  });
});

// ─── parseHost ──────────────────────────────────────────────────────────────
describe('parseHost', () => {
  it('returns null for empty / whitespace input', () => {
    expect(parseHost('')).toBeNull();
    expect(parseHost('   ')).toBeNull();
  });

  it('accepts bare host and applies the default TCP port', () => {
    expect(parseHost('192.168.1.42')).toBe('tcp://192.168.1.42:4321');
    expect(parseHost('pi.local')).toBe('tcp://pi.local:4321');
  });

  it('accepts host:port', () => {
    expect(parseHost('192.168.1.42:5000')).toBe('tcp://192.168.1.42:5000');
  });

  it('accepts and normalizes a tcp:// prefix', () => {
    expect(parseHost('tcp://10.0.0.5:9999')).toBe('tcp://10.0.0.5:9999');
    expect(parseHost('tcp://10.0.0.5')).toBe('tcp://10.0.0.5:4321');
  });

  it('rejects an invalid port', () => {
    expect(parseHost('host:0')).toBeNull();
    expect(parseHost('host:99999')).toBeNull();
    expect(parseHost('host:abc')).toBeNull();
  });

  it('rejects an IPv6-style address with multiple colons', () => {
    expect(parseHost('::1')).toBeNull();
    expect(parseHost('a:b:c')).toBeNull();
  });
});

// ─── pickConnection flow ────────────────────────────────────────────────────
function modalTermWithDraws() {
  const events: string[] = [];
  const draws: string[] = [];
  const queue: string[] = [];
  const waiters: Array<(k: string) => void> = [];
  return {
    events,
    draws,
    feed(k: string) {
      const w = waiters.shift();
      if (w) w(k);
      else queue.push(k);
    },
    term: {
      setup: () => { events.push('setup'); },
      teardown: () => { events.push('teardown'); },
      draw: (s: string) => { events.push('draw'); draws.push(s); },
      drawFooter: (s: string) => { events.push('drawFooter'); draws.push(s); return true; },
      showCursor: () => { events.push('show'); },
      hideCursor: () => { events.push('hide'); },
      waitKey: () => {
        if (queue.length > 0) return Promise.resolve(queue.shift()!);
        return new Promise<string>((r) => waiters.push(r));
      },
      delay: (_ms: number) => Promise.resolve(),
    },
  };
}

const dummyConn = {
  send: () => {},
  onMessage: () => {},
  onClose: () => {},
  close: () => {},
};

describe('pickConnection', () => {
  const file = pathJoin(tmpdir(), 'ching-test-pick-' + process.pid + '.json');
  afterEach(() => { try { rmSync(file); } catch {} });

  it('Local play connects via unix and returns the right target', async () => {
    const t = modalTermWithDraws();
    saveProfile(file, { name: 'alice' });
    const calls: string[] = [];
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-local.sock',
      initialName: 'alice',
      initialLastHost: undefined,
      connectUnix: async (p) => { calls.push('unix:' + p); return dummyConn as never; },
      connectTcp: async (h, p) => { calls.push('tcp:' + h + ':' + p); return dummyConn as never; },
    });
    await Promise.resolve();
    t.feed('l');
    const result = await pickPromise;
    expect(result).not.toBeNull();
    expect(result!.target).toBe('/tmp/test-local.sock');
    expect(result!.name).toBe('alice');
    expect(calls).toEqual(['unix:/tmp/test-local.sock']);
  });

  it('Remote prompts for host then connects via TCP and persists lastHost', async () => {
    const t = modalTermWithDraws();
    saveProfile(file, { name: 'alice' });
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test.sock',
      initialName: 'alice',
      initialLastHost: undefined,
      connectUnix: async () => { throw new Error('no'); },
      connectTcp: async () => dummyConn as never,
    });
    await Promise.resolve();
    // 'r' opens the host prompt (was 'j', which collided with the room
    // menu's [J]oin by code).
    t.feed('r');
    for (const ch of '192.168.1.42') {
      await Promise.resolve();
      t.feed(ch);
    }
    await Promise.resolve();
    t.feed('\r');
    const result = await pickPromise;
    expect(result).not.toBeNull();
    expect(result!.target).toBe('tcp://192.168.1.42:4321');
    // Persisted to the session file so next run can press R+Enter to reuse it.
    const p = loadProfile(file);
    expect(p.lastHost).toBe('tcp://192.168.1.42:4321');
  });

  it('R + Enter on a blank input falls back to Local', async () => {
    const t = modalTermWithDraws();
    saveProfile(file, { name: 'alice' });
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-fallback.sock',
      initialName: 'alice',
      initialLastHost: undefined,
      connectUnix: async () => dummyConn as never,
      connectTcp: async () => { throw new Error('should not reach TCP'); },
    });
    await Promise.resolve();
    t.feed('r');
    await Promise.resolve();
    t.feed('\r');  // Empty input -> blank -> local
    const result = await pickPromise;
    expect(result!.target).toBe('/tmp/test-fallback.sock');
  });

  it('first run with no name prompts for one and persists it', async () => {
    const t = modalTermWithDraws();
    // No profile, no env: initialName === ''
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-fr.sock',
      initialName: '',
      initialLastHost: undefined,
      connectUnix: async () => dummyConn as never,
      connectTcp: async () => dummyConn as never,
    });
    await Promise.resolve();
    // Name prompt is open first. Type "bob" then Enter.
    for (const ch of 'bob') {
      t.feed(ch);
      await Promise.resolve();
    }
    t.feed('\r');
    await Promise.resolve();
    // Now connection menu shows; choose Local.
    t.feed('l');
    const result = await pickPromise;
    expect(result).not.toBeNull();
    expect(result!.name).toBe('bob');
    const persisted = loadProfile(file);
    expect(persisted.name).toBe('bob');
  });

  it('a failed connect shows an error and lets the user try again', async () => {
    const t = modalTermWithDraws();
    let unixAttempts = 0;
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-fail.sock',
      initialName: 'alice',
      initialLastHost: undefined,
      connectUnix: async () => {
        unixAttempts++;
        if (unixAttempts === 1) throw new Error('ECONNREFUSED');
        return dummyConn as never;
      },
      connectTcp: async () => dummyConn as never,
    });
    await Promise.resolve();
    t.feed('l'); // first attempt fails
    await Promise.resolve();
    await Promise.resolve();
    t.feed('l'); // second attempt succeeds
    const result = await pickPromise;
    expect(result).not.toBeNull();
    expect(unixAttempts).toBe(2);
    // An error frame was drawn between the two attempts.
    const errFrames = t.draws.filter((d) => d.includes('no local daemon'));
    expect(errFrames.length).toBeGreaterThan(0);
  });

  it('Q quits and returns null', async () => {
    const t = modalTermWithDraws();
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-q.sock',
      initialName: 'alice',
      initialLastHost: undefined,
      connectUnix: async () => dummyConn as never,
      connectTcp: async () => dummyConn as never,
    });
    await Promise.resolve();
    t.feed('q');
    const result = await pickPromise;
    expect(result).toBeNull();
  });
});

// ─── end-to-end: connection menu (step 1) → room menu (step 2) ──────────────
// These two tests are the user-facing acceptance check: from a fresh client,
// you choose Local OR Remote, land on the room menu, and either Create or
// Join a code. Both transports route through the same step-2 menu.
describe('two-step flow: connect then choose a room action', () => {
  const file = pathJoin(tmpdir(), 'ching-flow-' + process.pid + '.json');
  afterEach(() => { try { rmSync(file); } catch {} });

  it('Local -> Create sends exactly one CREATE_ROOM after the room menu draws', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    saveProfile(file, { name: 'alice' });

    // Step 1: pickConnection drives the connection menu.
    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/flow-local.sock',
      initialName: 'alice',
      initialLastHost: undefined,
      connectUnix: async () => c.conn as never,
      connectTcp: async () => { throw new Error('should not reach TCP on Local path'); },
    });
    await pump();
    t.deliverKey('l');
    const picked = await pickPromise;
    expect(picked).not.toBeNull();
    expect(picked!.target).toBe('/tmp/flow-local.sock');

    // Step 1's frame had "step 1 of 2" so the player knows there's more coming.
    expect(t.draws.some((d) => d.includes('step 1 of 2'))).toBe(true);

    // Step 2: runClient takes the conn forward.
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: picked!.target,
      sessionFile: file,
      name: picked!.name,
      token: null,
    });
    await pump();
    c.inject({ v: 1, t: 'WELCOME', token: 'tok-1' });
    await pump();

    // The step-2 room menu must have been painted before any action.
    expect(t.draws.some((d) => d.includes('step 2 of 2') && d.includes('reate room'))).toBe(true);

    // Press C; CREATE_ROOM must reach the daemon exactly once.
    t.deliverKey('c');
    await pump();
    const creates = c.sent.filter((m) => m.t === 'CREATE_ROOM');
    expect(creates.length).toBe(1);

    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    await runPromise;
  });

  it('Remote -> Join by code sends exactly one JOIN_ROOM with the typed code', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    saveProfile(file, { name: 'bob' });

    const pickPromise = pickConnection({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/flow-remote.sock',
      initialName: 'bob',
      initialLastHost: undefined,
      connectUnix: async () => { throw new Error('should not reach unix on Remote path'); },
      connectTcp: async () => c.conn as never,
    });
    await pump();
    // Open Remote prompt.
    t.deliverKey('r');
    // Type host and confirm.
    for (const ch of '192.168.1.42') {
      await pump();
      t.deliverKey(ch);
    }
    await pump();
    t.deliverKey('\r');
    const picked = await pickPromise;
    expect(picked).not.toBeNull();
    expect(picked!.target).toBe('tcp://192.168.1.42:4321');

    // Now in step 2 over TCP. Same menu.
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: picked!.target,
      sessionFile: file,
      name: picked!.name,
      token: null,
    });
    await pump();
    c.inject({ v: 1, t: 'WELCOME', token: 'tok-1' });
    await pump();
    expect(t.draws.some((d) => d.includes('step 2 of 2'))).toBe(true);

    // Join a code: J, then 4 chars.
    t.deliverKey('j');
    await pump();
    for (const ch of ['Z', 'S', 'Q', 'G']) {
      t.deliverKey(ch);
      await pump();
    }
    await pump();
    const joins = c.sent.filter((m) => m.t === 'JOIN_ROOM');
    expect(joins.length).toBe(1);
    expect((joins[0] as { code: string }).code).toBe('ZSQG');

    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    await runPromise;
  });
});

// ─── runClient join flow (state-machine integration) ────────────────────────
describe('runClient join flow', () => {
  it('J + Z,S,Q,G sends exactly one JOIN_ROOM with code ZSQG and lobby paints after ROOM_STATE', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json',
      name: 'alice', token: null,
    });
    await pump();
    // Server welcomes; no seat hint -> still at menu.
    c.inject({ v: 1, t: 'WELCOME', token: 'tok-1' });
    await pump();
    // User opens the modal.
    t.deliverKey('j');
    await pump();
    // User types code one key at a time.
    for (const k of ['Z', 'S', 'Q', 'G']) {
      t.deliverKey(k);
      await pump();
    }
    await pump();
    const joinMsgs = c.sent.filter((m) => m.t === 'JOIN_ROOM');
    expect(joinMsgs.length).toBe(1);
    expect((joinMsgs[0] as { code: string }).code).toBe('ZSQG');
    // Server confirms membership with ROOM_STATE.
    c.inject({
      v: 1, t: 'ROOM_STATE', code: 'ZSQG', host: 0, phase: 'lobby',
      seats: [{ seat: 0, name: 'alice', kind: 'human', ready: false, connected: true }],
    });
    await pump();
    // After ROOM_STATE, the LATEST draw must be the lobby (no menu bounce).
    // The lobby frame contains 'ROOM  ZSQG'; the menu contains 'CHING · MULTIPLAYER'.
    const lobbyIdx = t.draws.findIndex((d) => d.includes('ROOM  ZSQG'));
    expect(lobbyIdx).toBeGreaterThanOrEqual(0);
    const drawsAfterLobby = t.draws.slice(lobbyIdx + 1);
    const menuAfterLobby = drawsAfterLobby.some((d) => d.includes('CHING · MULTIPLAYER'));
    expect(menuAfterLobby).toBe(false);
    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    await runPromise;
  });

  it('partial code + ESC cancels with empty buffer; the next J starts fresh', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json',
      name: 'alice', token: null,
    });
    await pump();
    c.inject({ v: 1, t: 'WELCOME', token: 'tok-1' });
    await pump();
    // First attempt: J, type 'A','B', then ESC.
    t.deliverKey('j');
    await pump();
    t.deliverKey('A');
    await pump();
    t.deliverKey('B');
    await pump();
    t.deliverKey('\x1b');
    await pump();
    // No JOIN_ROOM should have been sent.
    expect(c.sent.filter((m) => m.t === 'JOIN_ROOM').length).toBe(0);
    // Second attempt: J + ZSQG.
    t.deliverKey('j');
    await pump();
    for (const k of ['Z', 'S', 'Q', 'G']) {
      t.deliverKey(k);
      await pump();
    }
    await pump();
    const joinMsgs = c.sent.filter((m) => m.t === 'JOIN_ROOM');
    expect(joinMsgs.length).toBe(1);
    // Code must be exactly the second attempt — no carryover from the cancelled one.
    expect((joinMsgs[0] as { code: string }).code).toBe('ZSQG');
    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    await runPromise;
  });

  it('TURN_REMINDER for the current seat updates the footer in place (no full redraw)', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json',
      name: 'alice', token: null,
    });
    await pump();
    c.inject({ v: 1, t: 'WELCOME', token: 'tok-1' });
    await pump();
    // Drop the client into a 2-player game with seat 1 active.
    c.inject({
      v: 1, t: 'ROOM_STATE', code: 'ABCD', host: 0, phase: 'playing',
      seats: [
        { seat: 0, name: 'alice', kind: 'human', ready: true, connected: true },
        { seat: 1, name: 'bob', kind: 'human', ready: true, connected: false },
      ],
    });
    c.inject({
      v: 1, t: 'GAME_STATE',
      state: {
        players: [{ id: 'alice', tiles: [] }, { id: 'bob', tiles: [] }],
        current: 1, centerTiles: [21, 22, 23], diceInHand: 8, rolled: [],
        setAside: [], pickedFaces: [], phase: 'roll',
      },
      viewerSeat: 0,
      seats: [
        { seat: 0, name: 'alice', kind: 'human', ready: true, connected: true },
        { seat: 1, name: 'bob', kind: 'human', ready: true, connected: false },
      ],
    });
    await pump();
    const eventsBefore = t.events.length;
    // Three countdown ticks. Each should drawFooter, not a full draw.
    c.inject({ v: 1, t: 'TURN_REMINDER', seat: 1, secondsLeft: 15 });
    await pump();
    c.inject({ v: 1, t: 'TURN_REMINDER', seat: 1, secondsLeft: 10 });
    await pump();
    c.inject({ v: 1, t: 'TURN_REMINDER', seat: 1, secondsLeft: 5 });
    await pump();
    const newEvents = t.events.slice(eventsBefore);
    const footerOnly = newEvents.filter((e) => e === 'drawFooter');
    const fullDraws = newEvents.filter((e) => e === 'draw');
    expect(footerOnly.length).toBe(3);
    expect(fullDraws.length).toBe(0);
    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    await runPromise;
  });

  it('does not send JOIN_ROOM until the 4th character lands', async () => {
    const c = fakeConn();
    const t = fakeTerm();
    const runPromise = runClient(c.conn as never, t.term as never, {
      target: '/tmp/fake.sock', sessionFile: '/tmp/fake-session.json',
      name: 'alice', token: null,
    });
    await pump();
    c.inject({ v: 1, t: 'WELCOME', token: 'tok-1' });
    await pump();
    t.deliverKey('j');
    await pump();
    for (const k of ['Z', 'S', 'Q']) {
      t.deliverKey(k);
      await pump();
      // Still 0 JOIN_ROOMs.
      expect(c.sent.filter((m) => m.t === 'JOIN_ROOM').length).toBe(0);
    }
    t.deliverKey('G');
    await pump();
    expect(c.sent.filter((m) => m.t === 'JOIN_ROOM').length).toBe(1);
    c.inject({ v: 1, t: 'BYE', reason: 'replaced' });
    await runPromise;
  });
});
