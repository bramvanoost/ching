// Launcher routing tests. Verify that the top menu and multiplayer sub-menu
// dispatch to the right backend: [1] -> runSolo; [2H] -> ensureLocalDaemon
// + connectUnix + runClient with intent=create; [2J] -> host prompt + code
// prompt + connectTcp + runClient with intent=join. The auto-daemon spawn
// itself is integration-level (real child_process, real socket) and only
// noted here; the test injects a fake ensureLocalDaemon so we keep the unit
// suite hermetic.

import { afterEach, describe, expect, it } from 'vitest';
import { tmpdir } from 'node:os';
import { join as pathJoin } from 'node:path';
import { rmSync } from 'node:fs';
import { runLauncher } from '../src/launcher.js';
import { saveProfile } from '../src/client.js';

function fakeTerm() {
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

async function pump(): Promise<void> {
  for (let i = 0; i < 4; i++) await Promise.resolve();
}

const fakeConn = {
  send: () => {},
  onMessage: () => {},
  onClose: () => {},
  close: () => {},
};

describe('launcher routing', () => {
  const file = pathJoin(tmpdir(), 'ching-launcher-' + process.pid + '.json');
  afterEach(() => { try { rmSync(file); } catch {} });

  it('top menu [1] calls runSolo and exits', async () => {
    const t = fakeTerm();
    saveProfile(file, { name: 'alice' });
    let soloCalls = 0;
    const promise = runLauncher({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-launcher.sock',
      runSolo: async () => { soloCalls++; },
      ensureLocalDaemon: async () => { throw new Error('should not call'); },
      connectUnix: async () => { throw new Error('should not call'); },
      connectTcp: async () => { throw new Error('should not call'); },
      runClient: async () => { throw new Error('should not call'); },
    });
    await pump();
    t.feed('1');
    const result = await promise;
    expect(soloCalls).toBe(1);
    expect(result.exitCode).toBe(0);
    expect(result.spawnedChild).toBeNull();
  });

  it('top menu [Q] quits without calling anything', async () => {
    const t = fakeTerm();
    saveProfile(file, { name: 'alice' });
    const promise = runLauncher({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-launcher.sock',
      runSolo: async () => { throw new Error('should not call'); },
      ensureLocalDaemon: async () => { throw new Error('should not call'); },
      connectUnix: async () => { throw new Error('should not call'); },
      connectTcp: async () => { throw new Error('should not call'); },
      runClient: async () => { throw new Error('should not call'); },
    });
    await pump();
    t.feed('q');
    const result = await promise;
    expect(result.exitCode).toBe(0);
  });

  it('[2] -> [H]ost routes through ensureLocalDaemon, connectUnix, runClient with intent=create', async () => {
    const t = fakeTerm();
    saveProfile(file, { name: 'alice' });
    const trace: string[] = [];
    let runClientIntent: unknown = null;
    const promise = runLauncher({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-host.sock',
      runSolo: async () => { throw new Error('should not call'); },
      ensureLocalDaemon: async (sockPath) => {
        trace.push('ensureLocalDaemon:' + sockPath);
        return { spawnedChild: null };
      },
      connectUnix: async (sockPath) => {
        trace.push('connectUnix:' + sockPath);
        return fakeConn as never;
      },
      connectTcp: async () => { throw new Error('should not call'); },
      runClient: async (_c, _t, opts) => {
        trace.push('runClient:' + opts.target);
        runClientIntent = opts.intent;
        return 0;
      },
    });
    await pump();
    t.feed('2');
    await pump();
    t.feed('h');
    const result = await promise;
    expect(trace).toEqual([
      'ensureLocalDaemon:/tmp/test-host.sock',
      'connectUnix:/tmp/test-host.sock',
      'runClient:/tmp/test-host.sock',
    ]);
    expect(runClientIntent).toEqual({ kind: 'create' });
    expect(result.exitCode).toBe(0);
  });

  it('[2] -> [J]oin remote prompts host then code, routes through connectTcp + runClient intent=join', async () => {
    const t = fakeTerm();
    saveProfile(file, { name: 'alice' });
    const trace: string[] = [];
    let runClientOpts: { target: string; intent: unknown } | null = null;
    const promise = runLauncher({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-join.sock',
      runSolo: async () => { throw new Error('should not call'); },
      ensureLocalDaemon: async () => { throw new Error('should not call'); },
      connectUnix: async () => { throw new Error('should not call'); },
      connectTcp: async (host, port) => {
        trace.push('connectTcp:' + host + ':' + port);
        return fakeConn as never;
      },
      runClient: async (_c, _t, opts) => {
        runClientOpts = { target: opts.target, intent: opts.intent ?? null };
        return 0;
      },
    });
    await pump();
    t.feed('2');
    await pump();
    t.feed('j');
    await pump();
    // Host prompt: type "192.168.1.42" + Enter.
    for (const ch of '192.168.1.42') {
      t.feed(ch);
      await pump();
    }
    t.feed('\r');
    await pump();
    // Code prompt: 4 chars (filtered by CODE_CHARS set; B/D/E/F all valid).
    for (const ch of ['B', 'D', 'E', 'F']) {
      t.feed(ch);
      await pump();
    }
    const result = await promise;
    expect(trace).toEqual(['connectTcp:192.168.1.42:4321']);
    expect(runClientOpts).not.toBeNull();
    expect(runClientOpts!.target).toBe('tcp://192.168.1.42:4321');
    expect(runClientOpts!.intent).toEqual({ kind: 'join', code: 'BDEF' });
    expect(result.exitCode).toBe(0);
  });

  it('first-run with empty profile + no env prompts for a name and persists it', async () => {
    const t = fakeTerm();
    // No saveProfile() call: file does not exist.
    const prev = process.env.CHING_NAME;
    delete process.env.CHING_NAME;
    try {
      let soloCalls = 0;
      const promise = runLauncher({
        term: t.term as never,
        sessionFile: file,
        defaultSockPath: '/tmp/test-firstrun.sock',
        runSolo: async () => { soloCalls++; },
        ensureLocalDaemon: async () => { throw new Error('should not call'); },
        connectUnix: async () => { throw new Error('should not call'); },
        connectTcp: async () => { throw new Error('should not call'); },
        runClient: async () => { throw new Error('should not call'); },
      });
      await pump();
      // Name modal is open first.
      for (const ch of 'bob') {
        t.feed(ch);
        await pump();
      }
      t.feed('\r');
      await pump();
      // Top menu shown; pick Single.
      t.feed('1');
      const result = await promise;
      expect(soloCalls).toBe(1);
      expect(result.exitCode).toBe(0);
    } finally {
      if (prev === undefined) delete process.env.CHING_NAME;
      else process.env.CHING_NAME = prev;
    }
  });

  it('[2] then [B]ack returns to the top menu without connecting', async () => {
    const t = fakeTerm();
    saveProfile(file, { name: 'alice' });
    let soloCalls = 0;
    const promise = runLauncher({
      term: t.term as never,
      sessionFile: file,
      defaultSockPath: '/tmp/test-back.sock',
      runSolo: async () => { soloCalls++; },
      ensureLocalDaemon: async () => { throw new Error('should not call'); },
      connectUnix: async () => { throw new Error('should not call'); },
      connectTcp: async () => { throw new Error('should not call'); },
      runClient: async () => { throw new Error('should not call'); },
    });
    await pump();
    t.feed('2');
    await pump();
    t.feed('b');
    await pump();
    // Back at top menu; pick Single.
    t.feed('1');
    const result = await promise;
    expect(soloCalls).toBe(1);
    expect(result.exitCode).toBe(0);
  });
});
