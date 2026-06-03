// Unified player-facing entry point: `npm run ching`.
//
// Flow:
//   1. Term setup once at the top.
//   2. First-run name prompt if no persisted name and no CHING_NAME.
//   3. Top menu: [1] Single player (solo vs AI), [2] Multiplayer, [N] rename, [Q] quit.
//   4. Multiplayer sub-menu: [H]ost (auto-spawn local daemon if needed,
//      then Create), [J]oin remote (prompt for host IP + code, then Join),
//      [N] rename, [Q] quit.
//   5. Solo path runs the existing cli.ts game loop, byte-identical.
//
// The standalone `npm run play` and `npm run join` entries still work and
// hit the same underlying code paths (cli.ts main + client.ts main), so
// nothing breaks for users with muscle memory.
//
// Auto-spawned daemons are managed children of the launcher: they exit
// when the launcher exits (SIGINT, SIGTERM, normal exit). For an always-on
// daemon (Pi setup), run `npm run daemon` separately as before; the
// launcher will detect it on the socket and skip spawning.

import { spawn, type ChildProcess } from 'node:child_process';
import * as net from 'node:net';
import { fileURLToPath } from 'node:url';
import { dirname, join as pathJoin } from 'node:path';
import {
  BOLD,
  CLEAR,
  DIM_TEXT,
  P_LIME,
  P_LIME2,
  RED,
  RESET,
  TEXT,
  fg,
  panelBottom,
  panelLine,
  panelTop,
} from './render.js';
import {
  drawFrame,
  setupTerm,
  teardownTerm,
} from './term.js';
import {
  DEFAULT_SOCK,
  DEFAULT_TCP_PORT,
  connectTcp,
  connectUnix,
  loadProfile,
  parseHost,
  parseTcpTarget,
  readCode,
  readHost,
  readName,
  realTerm,
  resolveSessionFile,
  runClient,
  saveProfile,
  type Conn,
  type RoomIntent,
  type Term,
} from './client.js';
import { runSolo, DEFAULT_DISCIPLINE, parseDiscipline } from './cli.js';

// ─── menu frames ────────────────────────────────────────────────────────────
export function topMenuFrame(name: string, error: string | null): string {
  const buf: string[] = [CLEAR, '\n\n'];
  buf.push(panelTop('CHING  ·  push your luck, bank coins, ka-ching') + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(DIM_TEXT) + 'you: ' + RESET +
    fg(TEXT) + BOLD + name + RESET + '   ' +
    fg(DIM_TEXT) + '([N] to rename)' + RESET,
  ) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + '1' + RESET + fg(P_LIME) + '] Single player' + RESET +
    '    ' + fg(DIM_TEXT) + 'vs AI, no network, no daemon' + RESET,
  ) + '\n');
  buf.push(panelLine(
    '  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + '2' + RESET + fg(P_LIME) + '] Multiplayer' + RESET +
    '       ' + fg(DIM_TEXT) + 'host on this machine or join over LAN' + RESET,
  ) + '\n');
  buf.push(panelLine('  ' + fg(DIM_TEXT) + '[Q]uit' + RESET) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelBottom() + '\n');
  if (error) buf.push('   ' + fg(RED) + 'err: ' + error + RESET);
  else buf.push('   ' + fg(DIM_TEXT) + '> _' + RESET);
  return buf.join('');
}

export function multiMenuFrame(args: {
  name: string;
  lastHost: string | undefined;
  error: string | null;
}): string {
  const buf: string[] = [CLEAR, '\n\n'];
  buf.push(panelTop('CHING · MULTIPLAYER') + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(DIM_TEXT) + 'you: ' + RESET +
    fg(TEXT) + BOLD + args.name + RESET,
  ) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'H' + RESET + fg(P_LIME) + ']ost' + RESET +
    '            ' + fg(DIM_TEXT) + 'create a room on this machine; auto-starts a daemon if needed' + RESET,
  ) + '\n');
  const last = args.lastHost ? args.lastHost.replace(/^tcp:\/\//, '') : '(none yet)';
  buf.push(panelLine(
    '  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'J' + RESET + fg(P_LIME) + ']oin remote' + RESET +
    '     ' + fg(DIM_TEXT) + 'enter the host IP, then the room code — last: ' + last + RESET,
  ) + '\n');
  buf.push(panelLine('  ' + fg(DIM_TEXT) + '[B]ack' + RESET) + '\n');
  buf.push(panelBottom() + '\n');
  if (args.error) buf.push('   ' + fg(RED) + 'err: ' + args.error + RESET);
  else buf.push('   ' + fg(DIM_TEXT) + '> _' + RESET);
  return buf.join('');
}

// ─── auto-spawn local daemon ────────────────────────────────────────────────
// Tries to reach an existing daemon on the unix socket. If none, spawn one as
// a child process and wait for it to bind. The child is non-detached, so a
// SIGINT to the launcher propagates to it and the daemon dies cleanly. If
// you want a daemon that outlives the launcher, run `npm run daemon`
// separately and we'll detect it here.
export async function probeDaemon(sockPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const probe = net.createConnection(sockPath);
    const timeout = setTimeout(() => {
      try { probe.destroy(); } catch {}
      resolve(false);
    }, 500);
    probe.once('connect', () => {
      clearTimeout(timeout);
      try { probe.destroy(); } catch {}
      resolve(true);
    });
    probe.once('error', () => {
      clearTimeout(timeout);
      resolve(false);
    });
  });
}

export function spawnLocalDaemon(): ChildProcess {
  const here = dirname(fileURLToPath(import.meta.url));
  const daemonPath = pathJoin(here, 'net', 'daemon.ts');
  // npx + tsx so we don't require a build step. In a packaged build this
  // would target the compiled .js path instead.
  const child = spawn('npx', ['tsx', daemonPath], {
    // Mute the daemon's stdout/stderr — the launcher owns the TTY. If the
    // user wants daemon logs, run `npm run daemon` standalone.
    stdio: ['ignore', 'ignore', 'ignore'],
    detached: false,
  });
  return child;
}

export async function waitForDaemon(
  sockPath: string,
  opts: { timeoutMs?: number; stepMs?: number } = {},
): Promise<void> {
  const timeoutMs = opts.timeoutMs ?? 5_000;
  const stepMs = opts.stepMs ?? 100;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await probeDaemon(sockPath)) return;
    await new Promise<void>((r) => setTimeout(r, stepMs));
  }
  throw new Error('daemon did not start in ' + timeoutMs + 'ms');
}

// ─── launcher core ──────────────────────────────────────────────────────────
export type LauncherDeps = {
  term: Term;
  sessionFile: string;
  defaultSockPath: string;
  // Injectable for tests.
  runSolo: (opts: { discipline?: number }) => Promise<void>;
  ensureLocalDaemon: (sockPath: string) => Promise<{ spawnedChild: ChildProcess | null }>;
  connectUnix: (sockPath: string) => Promise<Conn>;
  connectTcp: (host: string, port: number) => Promise<Conn>;
  runClient: (conn: Conn, term: Term, opts: {
    target: string;
    sessionFile: string;
    name: string;
    token: string | null;
    intent?: RoomIntent;
  }) => Promise<number>;
};

export type LauncherResult = {
  exitCode: number;
  spawnedChild: ChildProcess | null;
};

export async function runLauncher(deps: LauncherDeps): Promise<LauncherResult> {
  const { term, sessionFile, defaultSockPath } = deps;
  const profile = loadProfile(sessionFile);
  let name = process.env.CHING_NAME ?? profile.name ?? '';

  // First-run name prompt.
  if (name.trim() === '') {
    const got = await readName(term, '');
    if (got === null || got === '') return { exitCode: 0, spawnedChild: null };
    name = got;
    const p = loadProfile(sessionFile);
    p.name = name;
    saveProfile(sessionFile, p);
  }

  let topError: string | null = null;
  while (true) {
    term.draw(topMenuFrame(name, topError));
    topError = null;
    let raw: string;
    try { raw = await term.waitKey(); } catch { return { exitCode: 1, spawnedChild: null }; }
    const k = (raw ?? '').toLowerCase();

    if (k === 'q' || k === '\x1b') return { exitCode: 0, spawnedChild: null };

    if (k === 'n') {
      const renamed = await readName(term, name);
      if (renamed && renamed.trim() !== '') {
        name = renamed;
        const p = loadProfile(sessionFile);
        p.name = name;
        saveProfile(sessionFile, p);
      }
      continue;
    }

    if (k === '1') {
      // Solo vs AI. No daemon, no network. Identical to npm run play.
      await deps.runSolo({});
      return { exitCode: 0, spawnedChild: null };
    }

    if (k === '2') {
      const result = await multiplayerFlow(deps, name);
      if (result) return result;
      // result === null: user pressed [B]ack, return to top menu.
      continue;
    }
  }
}

async function multiplayerFlow(
  deps: LauncherDeps,
  name: string,
): Promise<LauncherResult | null> {
  const { term, sessionFile, defaultSockPath } = deps;
  let error: string | null = null;
  let spawnedChild: ChildProcess | null = null;

  while (true) {
    const profile = loadProfile(sessionFile);
    term.draw(multiMenuFrame({ name, lastHost: profile.lastHost, error }));
    error = null;
    let raw: string;
    try { raw = await term.waitKey(); } catch { return { exitCode: 1, spawnedChild }; }
    const k = (raw ?? '').toLowerCase();

    if (k === 'b' || k === '\x1b') return null;
    if (k === 'q') return { exitCode: 0, spawnedChild };

    if (k === 'h') {
      // Host: ensure a local daemon, connect, runClient with intent=create.
      try {
        const { spawnedChild: c } = await deps.ensureLocalDaemon(defaultSockPath);
        spawnedChild = c;
      } catch (e) {
        error = 'could not start local daemon: ' + (e instanceof Error ? e.message : String(e));
        continue;
      }
      let conn: Conn;
      try {
        conn = await deps.connectUnix(defaultSockPath);
      } catch {
        error = 'spawned daemon but could not connect to ' + defaultSockPath;
        continue;
      }
      const token = profile.tokens?.[defaultSockPath]?.token ?? null;
      const exitCode = await deps.runClient(conn, term, {
        target: defaultSockPath,
        sessionFile,
        name,
        token,
        intent: { kind: 'create' },
      });
      return { exitCode, spawnedChild };
    }

    if (k === 'j') {
      // Join remote: prompt for host, then for code.
      const lastBare = profile.lastHost
        ? profile.lastHost.replace(/^tcp:\/\//, '')
        : '';
      const hostInput = await readHost(term, lastBare);
      if (hostInput === null) { error = null; continue; }
      const target = hostInput.trim() === ''
        ? defaultSockPath
        : parseHost(hostInput);
      if (!target) {
        error = 'could not parse host: ' + hostInput;
        continue;
      }
      // Now the code prompt.
      const code = await readCode(term);
      if (code === null) { error = null; continue; }

      let conn: Conn;
      try {
        if (target.startsWith('tcp://')) {
          const { host, port } = parseTcpTarget(target);
          conn = await deps.connectTcp(host, port);
          const p = loadProfile(sessionFile);
          p.lastHost = target;
          if (!p.name) p.name = name;
          saveProfile(sessionFile, p);
        } else {
          conn = await deps.connectUnix(target);
        }
      } catch {
        error = 'could not reach ' + target;
        continue;
      }
      const updatedProfile = loadProfile(sessionFile);
      const token = updatedProfile.tokens?.[target]?.token ?? null;
      const exitCode = await deps.runClient(conn, term, {
        target,
        sessionFile,
        name,
        token,
        intent: { kind: 'join', code },
      });
      return { exitCode, spawnedChild };
    }
  }
}

// ─── entry ──────────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const discipline = parseDiscipline(process.argv.slice(2)) ?? DEFAULT_DISCIPLINE;
  const sessionFile = resolveSessionFile();

  setupTerm();

  let managedChild: ChildProcess | null = null;
  const killManaged = () => {
    if (managedChild) {
      try { managedChild.kill('SIGTERM'); } catch {}
      managedChild = null;
    }
  };

  const sigHandler = () => {
    killManaged();
    teardownTerm();
    process.exit(0);
  };
  process.on('SIGINT', sigHandler);
  process.on('SIGTERM', sigHandler);
  process.on('SIGHUP', sigHandler);
  // 'exit' fires for any termination path; kill synchronously so we don't
  // orphan an auto-spawned daemon the user can't find later.
  process.on('exit', () => { killManaged(); });

  try {
    const result = await runLauncher({
      term: realTerm,
      sessionFile,
      defaultSockPath: DEFAULT_SOCK,
      runSolo: (opts) => runSolo({ discipline: opts.discipline ?? discipline }),
      ensureLocalDaemon: async (sockPath) => {
        if (await probeDaemon(sockPath)) return { spawnedChild: null };
        const child = spawnLocalDaemon();
        managedChild = child;
        await waitForDaemon(sockPath);
        return { spawnedChild: child };
      },
      connectUnix,
      connectTcp,
      runClient,
    });
    managedChild = result.spawnedChild;
    killManaged();
    teardownTerm();
    process.exit(result.exitCode);
  } catch (err) {
    killManaged();
    teardownTerm();
    console.error(err);
    process.exit(1);
  }
}

const isEntry = process.argv[1] && import.meta.url === 'file://' + process.argv[1];
if (isEntry) {
  main().catch((err) => {
    teardownTerm();
    console.error(err);
    process.exit(1);
  });
}
