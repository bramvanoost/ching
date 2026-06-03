// CHING network client. Connects to the daemon over a unix socket, runs the
// lobby UX, and renders game screens using the same renderer the solo CLI
// uses. The terminal is restored to cooked mode on any exit path — BYE,
// socket close, signal, or unhandled error — so a network flap can never
// leave a wrecked terminal.

import * as net from 'node:net';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join as pathJoin } from 'node:path';
import {
  A_GLINT,
  BOLD,
  CLEAR,
  DIM_TEXT,
  ESC,
  P_BR,
  P_LIME,
  P_LIME2,
  P_MED,
  P_NEON,
  RED,
  RESET,
  TEXT,
  fg,
  flashFrame,
  panelBottom,
  panelLine,
  panelTop,
  renderFrame,
  renderGameOver,
  seatColor,
  type ViewOpts,
} from './render.js';
import {
  delay,
  drawFooter,
  drawFrame,
  hideCursor,
  playFlash,
  playRoll,
  setupTerm,
  showCursor,
  teardownTerm,
  waitKey,
} from './term.js';
import {
  FrameDecoder,
  encode,
  type C2S,
  type S2C,
  type SeatView,
} from './net/protocol.js';
import { lobbyFooter, viewOptsFor } from './clientcore.js';
import { COIN, type Action, type Face, type State } from './engine.js';

export const DEFAULT_SOCK = '/tmp/ching.sock';
export const DEFAULT_TCP_PORT = 4321;
const DEFAULT_SESSION_FILE = pathJoin(homedir(), '.ching', 'session.json');

// CHING_SESSION overrides the session file path. Lets two clients on the
// same OS account hold separate tokens (e.g. testing, or shared Pi accounts).
export function resolveSessionFile(): string {
  return process.env.CHING_SESSION ?? DEFAULT_SESSION_FILE;
}

// Parse user-typed host text into a canonical 'tcp://host:port' string, or
// null if it's not a usable host. Accepts: 'host', 'host:port', 'tcp://...'.
// Returns null for empty input so the caller can decide what blank means
// (the connection menu treats it as 'local').
export function parseHost(input: string): string | null {
  const trimmed = input.trim();
  if (trimmed === '') return null;
  const cleaned = trimmed.replace(/^tcp:\/\//, '');
  const colons = (cleaned.match(/:/g) ?? []).length;
  if (colons > 1) return null;  // IPv6 not supported (no bracketed form)
  let host: string;
  let port = DEFAULT_TCP_PORT;
  if (colons === 0) {
    host = cleaned;
  } else {
    const [h, p] = cleaned.split(':');
    host = h;
    const pn = Number(p);
    if (!Number.isFinite(pn) || pn <= 0 || pn > 65535) return null;
    port = pn;
  }
  if (!host) return null;
  return 'tcp://' + host + ':' + port;
}

export function parseTcpTarget(target: string): { host: string; port: number } {
  // target is always 'tcp://host:port' (produced by parseHost).
  const stripped = target.replace(/^tcp:\/\//, '');
  const [host, port] = stripped.split(':');
  return { host, port: Number(port) };
}

// ─── session profile persistence ────────────────────────────────────────────
// One file holds the player's display name, the last remote host they joined,
// and per-target reconnect tokens. Keyed by transport target string so a
// single file can serve both a local unix daemon and one or more LAN daemons.
//
// Legacy flat-map format ({"target": {token}}) is read-compatible so a user
// who upgrades doesn't lose their reconnect tokens; on next write we
// transparently migrate to the new shape.
export type Profile = {
  name?: string;
  lastHost?: string;  // canonical 'tcp://host:port' from a previous Join Remote
  tokens?: Record<string, { token: string }>;
};

export function loadProfile(sessionFile: string): Profile {
  try {
    const raw = JSON.parse(readFileSync(sessionFile, 'utf8')) as unknown;
    if (!raw || typeof raw !== 'object') return {};
    const obj = raw as Record<string, unknown>;
    // New format: any of the new top-level fields present.
    if ('name' in obj || 'lastHost' in obj || 'tokens' in obj) {
      const out: Profile = {};
      if (typeof obj.name === 'string') out.name = obj.name;
      if (typeof obj.lastHost === 'string') out.lastHost = obj.lastHost;
      if (obj.tokens && typeof obj.tokens === 'object') {
        const t: Record<string, { token: string }> = {};
        for (const [k, v] of Object.entries(obj.tokens as Record<string, unknown>)) {
          if (v && typeof v === 'object' && typeof (v as { token?: unknown }).token === 'string') {
            t[k] = { token: (v as { token: string }).token };
          }
        }
        out.tokens = t;
      }
      return out;
    }
    // Legacy: top-level keys are targets mapping to {token}.
    const tokens: Record<string, { token: string }> = {};
    for (const [k, v] of Object.entries(obj)) {
      if (v && typeof v === 'object' && typeof (v as { token?: unknown }).token === 'string') {
        tokens[k] = { token: (v as { token: string }).token };
      }
    }
    return { tokens };
  } catch {
    return {};
  }
}

export function saveProfile(sessionFile: string, profile: Profile): void {
  try {
    mkdirSync(dirname(sessionFile), { recursive: true });
    writeFileSync(sessionFile, JSON.stringify(profile, null, 2));
  } catch {}
}

// Back-compat shims used by tests and the message loop. New code should use
// loadProfile / saveProfile directly so name and lastHost stay coherent.
export function loadSession(
  sessionFile: string,
  target: string,
): { token: string | null; name: string } {
  const p = loadProfile(sessionFile);
  const token = p.tokens?.[target]?.token ?? null;
  const name = process.env.CHING_NAME ?? p.name ?? process.env.USER ?? 'player';
  return { token, name };
}

export function saveToken(
  sessionFile: string,
  target: string,
  token: string,
): void {
  const p = loadProfile(sessionFile);
  p.tokens = p.tokens ?? {};
  p.tokens[target] = { token };
  saveProfile(sessionFile, p);
}

// ─── transport ──────────────────────────────────────────────────────────────
export type Conn = {
  send: (m: C2S) => void;
  onMessage: (handler: (m: S2C) => void) => void;
  onClose: (handler: () => void) => void;
  close: () => void;
};

// Shared wiring: framing decoder + onMessage/onClose dispatch. Used by both
// unix and TCP transports. The protocol layer is identical over either.
function wireConn(socket: net.Socket): Conn {
  const decoder = new FrameDecoder();
  const onMsgHandlers: Array<(m: S2C) => void> = [];
  const onCloseHandlers: Array<() => void> = [];
  socket.on('data', (chunk) => {
    for (const m of decoder.push(chunk)) onMsgHandlers.forEach((h) => h(m as S2C));
  });
  socket.on('close', () => onCloseHandlers.forEach((h) => h()));
  socket.on('error', () => {});
  return {
    send: (m) => socket.write(encode(m)),
    onMessage: (h) => onMsgHandlers.push(h),
    onClose: (h) => onCloseHandlers.push(h),
    close: () => socket.end(),
  };
}

export function connectUnix(sockPath: string): Promise<Conn> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(sockPath);
    socket.once('connect', () => resolve(wireConn(socket)));
    socket.once('error', (err) => reject(err));
  });
}

export function connectTcp(host: string, port: number): Promise<Conn> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(port, host);
    socket.once('connect', () => resolve(wireConn(socket)));
    socket.once('error', (err) => reject(err));
  });
}

// ─── render: menus ──────────────────────────────────────────────────────────
// Step 1 of the join flow: pick which DAEMON to talk to. After this screen
// returns a conn, the room menu (step 2) shows the same [C]reate / [J]oin
// by code options over whichever transport we ended up on. This screen is
// about WHO you're connecting to, not what you do once you're there.
//
// `Local` here means "the daemon on this machine", not "play solo vs AI".
// Solo-vs-AI lives behind `npm run play`, not this menu.
export function connectionMenuFrame(args: {
  name: string;
  lastHost: string | undefined;
  error: string | null;
}): string {
  const buf: string[] = [CLEAR, '\n\n'];
  buf.push(panelTop('CHING  ·  step 1 of 2: connect to a daemon') + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(DIM_TEXT) + 'you: ' + RESET +
    fg(TEXT) + BOLD + args.name + RESET + '   ' +
    fg(DIM_TEXT) + '(press [N] to rename)' + RESET,
  ) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'L' + RESET + fg(P_LIME) + ']ocal' + RESET +
    '       ' + fg(DIM_TEXT) + 'daemon on this machine (unix socket)' + RESET,
  ) + '\n');
  const last = args.lastHost
    ? args.lastHost.replace(/^tcp:\/\//, '')
    : '(none yet)';
  buf.push(panelLine(
    '  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'R' + RESET + fg(P_LIME) + ']emote' + RESET +
    '      ' + fg(DIM_TEXT) + 'another machine on the LAN — last: ' + last + RESET,
  ) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine(
    '  ' + fg(DIM_TEXT) + 'next: pick [C]reate room or [J]oin by code' + RESET,
  ) + '\n');
  buf.push(panelLine('  ' + fg(DIM_TEXT) + '[Q]uit' + RESET) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelBottom() + '\n');
  if (args.error) buf.push('   ' + fg(RED) + 'err: ' + args.error + RESET);
  else buf.push('   ' + fg(DIM_TEXT) + '> _' + RESET);
  return buf.join('');
}

function intentWaitingFrame(intent: RoomIntent): string {
  const buf: string[] = [CLEAR, '\n\n'];
  const what = intent.kind === 'create'
    ? 'creating a new room…'
    : 'joining room ' + intent.code + '…';
  buf.push(panelTop('CHING · MULTIPLAYER') + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine('  ' + fg(P_LIME) + what + RESET) + '\n');
  buf.push(panelLine('  ' + fg(DIM_TEXT) + 'waiting for the daemon to respond' + RESET) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelBottom() + '\n');
  buf.push('   ' + fg(DIM_TEXT) + '[Q]uit' + RESET);
  return buf.join('');
}

function mainMenuFrame(error: string | null): string {
  const buf: string[] = [CLEAR, '\n\n'];
  buf.push(panelTop('CHING · MULTIPLAYER  ·  step 2 of 2: pick a room') + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine('  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'C' + RESET + fg(P_LIME) + ']reate room' + RESET + '     ' + fg(DIM_TEXT) + 'mint a code, share it with friends' + RESET) + '\n');
  buf.push(panelLine('  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'J' + RESET + fg(P_LIME) + ']oin by code' + RESET + '    ' + fg(DIM_TEXT) + 'type the 4-character code' + RESET) + '\n');
  buf.push(panelLine('  ' + fg(DIM_TEXT) + '[Q]uit' + RESET) + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelBottom() + '\n');
  if (error) buf.push('   ' + fg(RED) + 'err: ' + error + RESET);
  else buf.push('   ' + fg(DIM_TEXT) + '> _' + RESET);
  return buf.join('');
}

function lobbyFrame(args: {
  code: string;
  host: number;
  seats: SeatView[];
  mySeat: number;
  footer: string;
}): string {
  const buf: string[] = [CLEAR, '\n'];
  const hostName = args.seats[args.host]?.name ?? '?';
  buf.push(panelTop('ROOM  ' + args.code + '   (host: ' + hostName + ')') + '\n');
  buf.push(panelLine('') + '\n');
  for (const s of args.seats) {
    const num = (s.seat + 1).toString();
    const kindBadge = s.kind === 'ai' || s.kind === 'ai-takeover'
      ? fg(DIM_TEXT) + '◇  ' + s.kind + RESET
      : fg(seatColor(s.seat)) + '◆  human' + RESET;
    const readyTag = s.kind === 'ai'
      ? fg(DIM_TEXT) + 'ready' + RESET
      : s.connected
        ? (s.ready ? fg(A_GLINT) + 'ready' + RESET : fg(DIM_TEXT) + 'waiting' + RESET)
        : fg(RED) + 'disconnected' + RESET;
    const youTag = s.seat === args.mySeat ? fg(P_NEON) + ' (you)' + RESET : '';
    buf.push(
      panelLine(
        '  ' + fg(P_LIME) + num + RESET + '  ' +
        fg(seatColor(s.seat)) + BOLD + s.name.padEnd(14, ' ') + RESET +
        kindBadge + '   ' + readyTag + youTag,
      ) + '\n',
    );
  }
  if (args.seats.length < 4) {
    buf.push(panelLine('  ' + fg(DIM_TEXT) + '[+ empty seat]' + RESET) + '\n');
  }
  buf.push(panelLine('') + '\n');
  buf.push(panelBottom() + '\n');
  buf.push('   ' + args.footer);
  return buf.join('');
}

// ─── prompt text for game footer ────────────────────────────────────────────
function validPickFaces(state: State): Face[] {
  const faces: Face[] = [];
  for (const f of [1, 2, 3, 4, 5, 6] as Face[]) {
    if (state.pickedFaces.includes(f)) continue;
    if (!state.rolled.includes(f)) continue;
    faces.push(f);
  }
  return faces;
}

function promptText(state: State): string {
  if (state.phase === 'pick') {
    const faces = validPickFaces(state);
    const keys = faces
      .map((f) =>
        f === COIN
          ? fg(A_GLINT) + BOLD + 'C' + RESET
          : fg(TEXT) + BOLD + String(f) + RESET,
      )
      .join(' ');
    return (
      fg(P_LIME) + '> pick a face [' + keys + fg(P_LIME) + ']  ' +
      fg(DIM_TEXT) + '(Q to quit) ' + RESET
    );
  }
  const canStop = state.setAside.length > 0;
  const choices = [fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'R' + RESET + fg(P_LIME) + ']oll' + RESET];
  if (canStop) choices.push(fg(P_LIME) + '[' + fg(A_GLINT) + BOLD + 'S' + RESET + fg(P_LIME) + ']top' + RESET);
  choices.push(fg(DIM_TEXT) + '[Q]uit' + RESET);
  return fg(P_LIME) + '> ' + choices.join('  ') + ' ' + RESET;
}

function waitingFooter(activeName: string, reminder: { secondsLeft: number } | null): string {
  if (reminder) {
    return (
      fg(RED) + '> ' + activeName + ' disconnected — AI takes over in ' +
      reminder.secondsLeft + 's…' + RESET
    );
  }
  return fg(DIM_TEXT) + 'waiting for ' + activeName + '…' + RESET;
}

// ─── client lifecycle ───────────────────────────────────────────────────────
export type Term = {
  setup: () => void;
  teardown: () => void;
  draw: (s: string) => void;
  drawFooter: (footer: string) => boolean;
  showCursor: () => void;
  hideCursor: () => void;
  waitKey: () => Promise<string>;
  delay: (ms: number) => Promise<void>;
};

export { realTerm };

const realTerm: Term = {
  setup: setupTerm,
  teardown: teardownTerm,
  draw: drawFrame,
  drawFooter,
  showCursor,
  hideCursor,
  waitKey,
  delay,
};

export type ClientHandle = { shutdown: (code: number) => void };

// Optional auto-action the launcher pre-decided. When set, runClient skips
// the [C]reate / [J]oin by code main menu and fires the chosen message
// itself as soon as the daemon WELCOMEs. The user only sees the lobby.
export type RoomIntent =
  | { kind: 'create' }
  | { kind: 'join'; code: string };

export async function runClient(
  conn: Conn,
  term: Term,
  opts: {
    target: string;
    sessionFile: string;
    name: string;
    token: string | null;
    intent?: RoomIntent;
  },
): Promise<number> {
  type MenuKey = 'menu' | 'joining-code' | 'lobby' | 'game' | 'over';
  type LobbyData = { code: string; host: number; seats: SeatView[]; mySeat: number };
  type GameData = { code: string; seats: SeatView[]; mySeat: number };

  let exitCode = 0;
  let exited = false;
  let lastState: State | null = null;
  let menuKey: MenuKey = 'menu';
  let lastError: string | null = null;
  let lobbyData: LobbyData | null = null;
  let gameData: GameData | null = null;
  let reminder: { seat: number; secondsLeft: number } | null = null;
  // Modal flag suppresses server-pushed redraws while a modal owns the screen.
  // The outer input loop is already suspended at `await readCode(...)` so the
  // global hotkey block can't fire; this flag protects against the message
  // loop drawing OVER an open modal between keystrokes.
  let modalOpen = false;

  let resolveExit: () => void = () => {};
  const exitPromise = new Promise<void>((r) => { resolveExit = r; });

  const inbox: S2C[] = [];
  const waiters: Array<(m: S2C) => void> = [];
  conn.onMessage((m) => {
    if (waiters.length > 0) {
      waiters.shift()!(m);
    } else {
      inbox.push(m);
    }
  });

  function nextMsg(): Promise<S2C> {
    if (inbox.length > 0) return Promise.resolve(inbox.shift()!);
    return new Promise((r) => waiters.push(r));
  }

  // App-level heartbeat: send PING every 5s so the daemon's silent-drop
  // detector knows we're alive even when nothing else is happening (lobby
  // waiting, off-turn during a game). Cleared in exit() so tests don't
  // leak timers; unref() so this interval alone never keeps the event
  // loop alive.
  const PING_INTERVAL_MS = 5_000;
  let pingHandle: ReturnType<typeof setInterval> | null = null;

  function exit(code: number): void {
    if (exited) return;
    exited = true;
    exitCode = code;
    if (pingHandle) {
      clearInterval(pingHandle);
      pingHandle = null;
    }
    term.teardown();
    conn.close();
    resolveExit();
  }

  conn.onClose(() => {
    if (!exited) exit(1);
  });

  // Process incoming messages in the background.
  let messagesRunning = true;
  (async () => {
    while (messagesRunning) {
      const m = await nextMsg();
      if (m.t === 'WELCOME') {
        saveToken(opts.sessionFile, opts.target, m.token);
        if (m.seatHint) {
          menuKey = 'lobby';
        } else if (opts.intent) {
          // Launcher pre-decided the room action; auto-fire it so the user
          // never sees the [C]/[J] menu.
          if (opts.intent.kind === 'create') {
            conn.send({ v: 1, t: 'CREATE_ROOM' });
          } else {
            conn.send({ v: 1, t: 'JOIN_ROOM', code: opts.intent.code });
          }
        }
      } else if (m.t === 'ROOM_STATE') {
        const mySeatGuess = m.seats.findIndex((s) => s.name === opts.name);
        lobbyData = {
          code: m.code,
          host: m.host,
          seats: m.seats,
          mySeat: mySeatGuess !== -1 ? mySeatGuess : 0,
        };
        if (m.phase === 'lobby') {
          menuKey = 'lobby';
        } else if (m.phase === 'playing') {
          menuKey = 'game';
          if (gameData) gameData.seats = m.seats;
        } else if (m.phase === 'over') {
          menuKey = 'over';
        }
        // Server-pushed state change: paint it. Without this, every other
        // player's READY/JOIN/LEAVE was invisible until a local keypress.
        redrawCurrent();
      } else if (m.t === 'GAME_STATE') {
        const prev = lastState;
        lastState = m.state;
        gameData = { code: lobbyData?.code ?? '', seats: m.seats, mySeat: m.viewerSeat };
        if (m.state.phase === 'over') {
          menuKey = 'over';
        } else {
          menuKey = 'game';
        }
        await onGameState(prev, m.state, m.seats, m.viewerSeat, m.lastEvent);
      } else if (m.t === 'TURN_REMINDER') {
        reminder = { seat: m.seat, secondsLeft: m.secondsLeft };
        // Only the footer text (countdown number) changes between ticks.
        // Repaint the footer line in place to avoid a full-screen redraw
        // every 5 seconds (which can flicker or, under bad terminal config,
        // visibly stack frames).
        if (
          !modalOpen &&
          menuKey === 'game' &&
          gameData &&
          lastState &&
          lastState.current === m.seat
        ) {
          const seatName = gameData.seats[m.seat]?.name ?? '?';
          if (!term.drawFooter('   ' + waitingFooter(seatName, reminder))) {
            redrawCurrent();
          }
        } else {
          redrawCurrent();
        }
      } else if (m.t === 'ERROR') {
        lastError = m.code + ': ' + m.message;
        redrawCurrent();
      } else if (m.t === 'BYE') {
        exit(0);
        return;
      }
    }
  })();

  function lobbyFooterFor(): string {
    if (!lobbyData) return '';
    const isHost = lobbyData.mySeat === lobbyData.host;
    const parts: string[] = [
      fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'R' + RESET + fg(P_LIME) + ']eady' + RESET,
    ];
    if (isHost) {
      parts.push(
        fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'A' + RESET + fg(P_LIME) + ']dd AI' + RESET,
      );
      parts.push(
        fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'K' + RESET + fg(P_LIME) + ']ick seat' + RESET,
      );
      parts.push(
        fg(P_LIME) + '[' + fg(A_GLINT) + BOLD + 'S' + RESET + fg(P_LIME) + ']tart' + RESET,
      );
    }
    parts.push(fg(DIM_TEXT) + '[L]eave' + RESET);
    parts.push(fg(DIM_TEXT) + '[Q]uit' + RESET);
    const base = fg(P_LIME) + '> ' + parts.join('  ');
    return lastError ? base + '   ' + fg(RED) + 'err: ' + lastError + RESET : base;
  }

  function redrawGame(): void {
    if (!gameData || !lastState) return;
    const seatName = gameData.seats[lastState.current]?.name ?? '?';
    const isMine = lastState.current === gameData.mySeat;
    const footer = lastState.phase === 'over'
      ? ''
      : isMine
        ? promptText(lastState)
        : waitingFooter(seatName, reminder && reminder.seat === lastState.current ? reminder : null);
    const opts: ViewOpts = viewOptsFor(gameData.seats, gameData.mySeat, { footer });
    term.draw(renderFrame(lastState, opts));
  }

  // Single source of truth for what's on screen. Always reads the LIVE state
  // (menuKey, lobbyData, lastState), never a captured snapshot, so server
  // pushes that arrive between local keystrokes are reflected in the next
  // render. Modal-aware: refuses to draw while a modal owns the screen.
  function redrawCurrent(): void {
    if (modalOpen || exited) return;
    if (menuKey === 'menu') {
      term.draw(mainMenuFrame(lastError));
      return;
    }
    if (menuKey === 'lobby' && lobbyData) {
      term.draw(lobbyFrame({ ...lobbyData, footer: lobbyFooterFor() }));
      return;
    }
    if (menuKey === 'game') {
      redrawGame();
      return;
    }
    if (menuKey === 'over' && lastState && gameData) {
      term.draw(renderGameOver(lastState, viewOptsFor(gameData.seats, gameData.mySeat)));
    }
  }

  async function onGameState(
    prev: State | null,
    next: State,
    seats: SeatView[],
    viewer: number,
    lastEvent: 'banked' | 'stolen' | 'busted' | undefined,
  ): Promise<void> {
    // Roll-reveal: a fresh non-empty rolled[] arriving from server.
    const baseOpts = viewOptsFor(seats, viewer);
    if (
      prev &&
      prev.phase !== 'pick' &&
      next.phase === 'pick' &&
      next.rolled.length > 0
    ) {
      const partial: State = { ...next, rolled: [], phase: 'pick' };
      const rollFooter = fg(DIM_TEXT) + 'rolling…' + RESET;
      await playRoll(next.rolled, ({ rolledSoFar, spinIdx, spinFrame, spinGlint }) => {
        const visible = next.rolled.slice(0, rolledSoFar);
        const snap: State = { ...partial, rolled: visible };
        return renderFrame(snap, { ...baseOpts, footer: rollFooter, spinIdx, spinFrame, spinGlint });
      });
    }
    redrawGame();
    // Effects: ka-ching / steal / bust.
    if (lastEvent === 'banked') {
      await playFlash(flashFrame('◆  K A · C H I N G !  ◆', A_GLINT), true);
    } else if (lastEvent === 'stolen') {
      await playFlash(flashFrame('▶  S T E A L !  ◀', seatColor(prev?.current ?? 0)), true);
    } else if (lastEvent === 'busted') {
      await playFlash(flashFrame('✗  B U S T !  ✗', RED), false);
    }
    if (next.phase === 'over') {
      term.draw(renderGameOver(next, viewOptsFor(seats, viewer)));
    } else {
      redrawGame();
    }
  }

  // ─── input loop ────────────────────────────────────────────────────────────
  term.setup();
  conn.send({ v: 1, t: 'HELLO', name: opts.name, token: opts.token ?? undefined });

  pingHandle = setInterval(() => {
    if (!exited) conn.send({ v: 1, t: 'PING' });
  }, PING_INTERVAL_MS);
  // Don't keep the event loop alive just for this heartbeat. If the rest of
  // the program is done, exit cleanly rather than waiting on the timer.
  if (typeof (pingHandle as { unref?: () => void }).unref === 'function') {
    (pingHandle as { unref: () => void }).unref();
  }

  // With a launcher-supplied intent we never want the [C]/[J] menu to flash;
  // show a "waiting" frame instead. ROOM_STATE will paint over it.
  if (opts.intent) {
    term.draw(intentWaitingFrame(opts.intent));
  } else {
    term.draw(mainMenuFrame(null));
  }

  while (!exited) {
    const next = await Promise.race([
      term.waitKey().then((k) => ({ kind: 'key' as const, k })),
      exitPromise.then(() => ({ kind: 'exit' as const })),
    ]);
    if (next.kind === 'exit' || exited) break;
    const k = next.k.toLowerCase();
    const mk = menuKey as MenuKey;
    const lb = lobbyData as LobbyData | null;
    const gd = gameData as GameData | null;
    const st = lastState as State | null;
    if (k === 'q' && mk !== 'game') {
      exit(0);
      break;
    }
    if (mk === 'menu') {
      if (k === 'c') {
        conn.send({ v: 1, t: 'CREATE_ROOM' });
      } else if (k === 'j') {
        modalOpen = true;
        let code: string | null;
        try {
          code = await readCode(term);
        } finally {
          modalOpen = false;
        }
        // Repaint based on CURRENT state. If ROOM_STATE arrived during the
        // modal (rare, but possible) we draw the new state; otherwise we
        // restore the menu so the modal's prompt line doesn't linger.
        redrawCurrent();
        if (code === null) continue;
        conn.send({ v: 1, t: 'JOIN_ROOM', code });
      }
      continue;
    }
    if (mk === 'lobby' && lb) {
      if (k === 'r') {
        const me = lb.seats[lb.mySeat];
        conn.send({ v: 1, t: 'READY', ready: !me?.ready });
      } else if (k === 'a' && lb.mySeat === lb.host) {
        conn.send({ v: 1, t: 'ADD_AI_SEAT' });
      } else if (k === 'k' && lb.mySeat === lb.host) {
        modalOpen = true;
        let seat: number | null;
        try {
          seat = await readSeatNumber(term, lb.seats.length);
        } finally {
          modalOpen = false;
        }
        redrawCurrent();
        if (seat !== null) conn.send({ v: 1, t: 'REMOVE_SEAT', seat });
      } else if (k === 's' && lb.mySeat === lb.host) {
        conn.send({ v: 1, t: 'START' });
      } else if (k === 'l') {
        conn.send({ v: 1, t: 'LEAVE' });
      }
      // No stale-snapshot redraw here. ROOM_STATE / ERROR responses from the
      // daemon trigger redrawCurrent() with the LIVE lobbyData. That's how
      // the other player's READY / JOIN / LEAVE actually shows up on screen.
      continue;
    }
    if (mk === 'game' && gd && st) {
      if (st.current !== gd.mySeat) continue;
      const action = parseGameKey(k, st);
      if (action === 'quit') { conn.send({ v: 1, t: 'LEAVE' }); exit(0); break; }
      if (action) conn.send({ v: 1, t: 'ACTION', action });
      continue;
    }
    if (mk === 'over') {
      exit(0);
      break;
    }
  }

  messagesRunning = false;
  return exitCode;
}

function parseGameKey(k: string, state: State): Action | 'quit' | null {
  if (k === 'q') return 'quit';
  if (state.phase === 'pick') {
    if (k === 'c' || k === '$') {
      if (state.rolled.includes(COIN) && !state.pickedFaces.includes(COIN)) {
        return { type: 'PICK', face: COIN };
      }
      return null;
    }
    const n = Number(k);
    if (Number.isInteger(n) && n >= 1 && n <= 5) {
      const f = n as Face;
      if (state.rolled.includes(f) && !state.pickedFaces.includes(f)) {
        return { type: 'PICK', face: f };
      }
    }
    return null;
  }
  if (state.phase === 'roll') {
    if (k === 'r') return { type: 'ROLL' };
    if (k === 's' && state.setAside.length > 0) return { type: 'STOP' };
  }
  return null;
}

// Modal contract: while a modal is open, the outer input loop is suspended at
// `await readCode(...)` so the global hotkey block can't fire. ESC is the only
// cancel; every letter (including former hotkeys like Q/R/A/S) types into the
// field. Unknown / multi-char input (arrow keys, etc.) is dropped silently so
// the modal never throws. try/finally restores cursor state on any exit path.
//
// CODE_CHARS here is intentionally BROADER than the daemon's minting alphabet:
// the daemon won't mint codes containing reserved hotkey letters, but the
// field still accepts them so codes from older daemons (or hand-entered ones)
// are typeable.
export const CODE_CHARS = new Set('ABCDEFGHJKMNPQRSTUVWXYZ23456789'.split(''));

export async function readCode(term: Term): Promise<string | null> {
  let buf = '';
  let cancelled = false;
  term.draw(ESC + '?25h'); // show cursor
  try {
    while (buf.length < 4) {
      term.draw('\r   ' + fg(P_LIME) + '> code: ' + fg(TEXT) + buf + fg(DIM_TEXT) + '_'.repeat(4 - buf.length) + RESET);
      let raw: string;
      try {
        raw = await term.waitKey();
      } catch {
        cancelled = true;
        break;
      }
      if (typeof raw !== 'string' || raw.length === 0) continue;
      // ESC (raw or starting an escape sequence). Lone ESC cancels;
      // multi-char sequences like arrow keys (\x1b[A) are ignored.
      if (raw === '\x1b') { cancelled = true; break; }
      if (raw.charCodeAt(0) === 0x1b) continue;
      // Enter accepts what we have.
      if (raw === '\r' || raw === '\n') break;
      // Backspace.
      if (raw === '\x7f' || raw === '\b') {
        buf = buf.slice(0, -1);
        continue;
      }
      // Any other single character: try to type.
      if (raw.length === 1) {
        const k = raw.toUpperCase();
        if (CODE_CHARS.has(k)) buf += k;
      }
      // Anything else (multi-char paste, control chars) is silently ignored.
    }
    if (cancelled) return null;
    return buf.length === 4 ? buf : null;
  } finally {
    term.draw(ESC + '?25l');
  }
}

export async function readSeatNumber(term: Term, max: number): Promise<number | null> {
  term.draw('\r   ' + fg(P_LIME) + '> seat # (1-' + max + ', ESC cancels): ' + RESET);
  let raw: string;
  try {
    raw = await term.waitKey();
  } catch {
    return null;
  }
  if (typeof raw !== 'string' || raw.length !== 1) return null;
  if (raw === '\x1b') return null;
  const n = Number(raw);
  if (Number.isInteger(n) && n >= 1 && n <= max) return n - 1;
  return null;
}

// Generic free-text input modal. Same contract as readCode: ESC cancels (and
// is the only way to abort), Enter accepts, Backspace deletes, any printable
// single character types. Multi-char escape sequences (arrow keys, paste
// chunks) are dropped silently so the prompt never throws. The cursor is
// shown for the duration and hidden via try/finally.
export type ReadTextOpts = {
  prompt: string;
  initial?: string;
  maxLength?: number;
  allowEmpty?: boolean;  // if true, Enter on an empty buffer returns ''
};

export async function readText(term: Term, opts: ReadTextOpts): Promise<string | null> {
  const max = opts.maxLength ?? 32;
  let buf = (opts.initial ?? '').slice(0, max);
  let cancelled = false;
  term.draw(ESC + '?25h');
  try {
    while (true) {
      term.draw(
        '\r\x1b[2K   ' + fg(P_LIME) + '> ' + opts.prompt + ': ' +
        fg(TEXT) + buf + fg(DIM_TEXT) + '_' + RESET,
      );
      let raw: string;
      try {
        raw = await term.waitKey();
      } catch {
        cancelled = true;
        break;
      }
      if (typeof raw !== 'string' || raw.length === 0) continue;
      if (raw === '\x1b') { cancelled = true; break; }
      if (raw.charCodeAt(0) === 0x1b) continue;  // arrow-key sequence
      if (raw === '\r' || raw === '\n') {
        if (!opts.allowEmpty && buf.trim() === '') continue;
        break;
      }
      if (raw === '\x7f' || raw === '\b') {
        buf = buf.slice(0, -1);
        continue;
      }
      // Accept any single printable character.
      if (raw.length === 1 && raw.charCodeAt(0) >= 32 && buf.length < max) {
        buf += raw;
      }
    }
    if (cancelled) return null;
    return buf;
  } finally {
    term.draw(ESC + '?25l');
  }
}

export async function readName(term: Term, initial: string): Promise<string | null> {
  const v = await readText(term, { prompt: 'name', initial, maxLength: 16, allowEmpty: false });
  return v === null ? null : v.trim();
}

export async function readHost(term: Term, initial: string): Promise<string | null> {
  return readText(term, {
    prompt: 'host  (blank = local, ESC cancels)',
    initial, maxLength: 64, allowEmpty: true,
  });
}

// Pre-connect UI: prompt for name on first run if needed, then run the
// connection menu until the user picks a target the daemon is reachable on.
// Returns null on quit.
//
// The opts.connectUnix / opts.connectTcp injection points exist so the test
// can drive this without an actual network or filesystem socket.
export type PickConnectionOpts = {
  term: Term;
  sessionFile: string;
  defaultSockPath: string;
  initialName: string;
  initialLastHost: string | undefined;
  connectUnix: (sockPath: string) => Promise<Conn>;
  connectTcp: (host: string, port: number) => Promise<Conn>;
};

export type PickConnectionResult = {
  conn: Conn;
  target: string;
  name: string;
};

export async function pickConnection(
  opts: PickConnectionOpts,
): Promise<PickConnectionResult | null> {
  const { term, sessionFile, defaultSockPath } = opts;
  let name = opts.initialName;
  let lastHost = opts.initialLastHost;
  let error: string | null = null;

  // First-run name prompt: empty / missing persisted name AND no env override.
  if (!name || name.trim() === '') {
    const got = await readName(term, '');
    if (got === null || got === '') return null;
    name = got;
    const p = loadProfile(sessionFile);
    p.name = name;
    saveProfile(sessionFile, p);
  }

  while (true) {
    term.draw(connectionMenuFrame({ name, lastHost, error }));
    let raw: string;
    try {
      raw = await term.waitKey();
    } catch {
      return null;
    }
    const k = (raw ?? '').toLowerCase();
    if (k === 'q') return null;
    if (k === 'n') {
      const renamed = await readName(term, name);
      if (renamed && renamed.trim() !== '') {
        name = renamed;
        const p = loadProfile(sessionFile);
        p.name = name;
        saveProfile(sessionFile, p);
      }
      error = null;
      continue;
    }
    if (k === 'l') {
      try {
        const conn = await opts.connectUnix(defaultSockPath);
        return { conn, target: defaultSockPath, name };
      } catch {
        error = 'no local daemon at ' + defaultSockPath + ' (start it: npm run daemon)';
        continue;
      }
    }
    if (k === 'r') {
      const initial = lastHost ? lastHost.replace(/^tcp:\/\//, '') : '';
      const input = await readHost(term, initial);
      if (input === null) { error = null; continue; }
      if (input.trim() === '') {
        // Blank -> local.
        try {
          const conn = await opts.connectUnix(defaultSockPath);
          return { conn, target: defaultSockPath, name };
        } catch {
          error = 'no local daemon at ' + defaultSockPath;
          continue;
        }
      }
      const target = parseHost(input);
      if (!target) {
        error = 'could not parse host: ' + input;
        continue;
      }
      const { host, port } = parseTcpTarget(target);
      try {
        const conn = await opts.connectTcp(host, port);
        lastHost = target;
        const p = loadProfile(sessionFile);
        p.lastHost = target;
        if (!p.name) p.name = name;
        saveProfile(sessionFile, p);
        return { conn, target, name };
      } catch {
        error = 'could not reach ' + host + ':' + port;
        continue;
      }
    }
    // Any other key: redraw with the same state (clears any modal residue).
  }
}

// ─── entry point ────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const sessionFile = resolveSessionFile();
  const profile = loadProfile(sessionFile);

  // Term comes up once for the whole session. setup/teardown are idempotent
  // so runClient calling them again is safe.
  setupTerm();
  const sigHandler = (_sig: string) => {
    teardownTerm();
    process.exit(0);
  };
  process.on('SIGINT', () => sigHandler('SIGINT'));
  process.on('SIGTERM', () => sigHandler('SIGTERM'));

  try {
    // CHING_HOST stays as an override: skips the menu, connects directly.
    // Used for headless / scripted clients and the integration tests.
    const envHost = process.env.CHING_HOST;
    const envName = process.env.CHING_NAME;
    let conn: Conn;
    let target: string;
    let name: string;
    if (envHost) {
      const portRaw = process.env.CHING_PORT;
      const port = portRaw !== undefined ? Number(portRaw) : DEFAULT_TCP_PORT;
      if (!Number.isFinite(port) || port <= 0) {
        console.error('CHING_PORT must be a positive number');
        process.exit(1);
      }
      target = 'tcp://' + envHost + ':' + port;
      name = envName ?? profile.name ?? process.env.USER ?? 'player';
      try {
        conn = await connectTcp(envHost, port);
      } catch {
        teardownTerm();
        console.error('could not reach ' + envHost + ':' + port);
        process.exit(1);
        return;
      }
    } else {
      const initialName = envName ?? profile.name ?? '';
      const picked = await pickConnection({
        term: realTerm,
        sessionFile,
        defaultSockPath: DEFAULT_SOCK,
        initialName,
        initialLastHost: profile.lastHost,
        connectUnix,
        connectTcp,
      });
      if (!picked) {
        teardownTerm();
        process.exit(0);
        return;
      }
      conn = picked.conn;
      target = picked.target;
      name = picked.name;
    }

    const token = profile.tokens?.[target]?.token ?? null;
    const code = await runClient(conn, realTerm, {
      target,
      sessionFile,
      name,
      token,
    });
    process.exit(code);
  } catch (err) {
    teardownTerm();
    throw err;
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

// Re-export for tests.
export { mainMenuFrame, lobbyFrame, parseGameKey };
// Imports kept lint-clean.
void hideCursor; void lobbyFooter; void P_BR; void P_MED;
