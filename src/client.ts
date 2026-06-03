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

const DEFAULT_SOCK = '/tmp/ching.sock';
const DEFAULT_SESSION_FILE = pathJoin(homedir(), '.ching', 'session.json');

// CHING_SESSION overrides the session file path. Lets two clients on the
// same OS account hold separate tokens (e.g. testing, or shared Pi accounts).
export function resolveSessionFile(): string {
  return process.env.CHING_SESSION ?? DEFAULT_SESSION_FILE;
}

// ─── session token persistence ──────────────────────────────────────────────
// File keyed by socket path so the same file can hold tokens for multiple
// daemons. CHING_SESSION just picks which file is used.
type Session = Record<string, { token: string }>;

export function loadSession(
  sessionFile: string,
  sockPath: string,
): { token: string | null; name: string } {
  let token: string | null = null;
  try {
    const raw = JSON.parse(readFileSync(sessionFile, 'utf8')) as Session;
    if (raw[sockPath]?.token) token = raw[sockPath].token;
  } catch {}
  const name = process.env.CHING_NAME ?? process.env.USER ?? 'player';
  return { token, name };
}

export function saveToken(
  sessionFile: string,
  sockPath: string,
  token: string,
): void {
  let raw: Session = {};
  try {
    raw = JSON.parse(readFileSync(sessionFile, 'utf8')) as Session;
  } catch {}
  raw[sockPath] = { token };
  try {
    mkdirSync(dirname(sessionFile), { recursive: true });
    writeFileSync(sessionFile, JSON.stringify(raw, null, 2));
  } catch {}
}

// ─── transport ──────────────────────────────────────────────────────────────
type Conn = {
  send: (m: C2S) => void;
  onMessage: (handler: (m: S2C) => void) => void;
  onClose: (handler: () => void) => void;
  close: () => void;
};

function connectSocket(sockPath: string): Promise<Conn> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(sockPath);
    const decoder = new FrameDecoder();
    const onMsgHandlers: Array<(m: S2C) => void> = [];
    const onCloseHandlers: Array<() => void> = [];
    socket.once('connect', () => {
      socket.on('data', (chunk) => {
        for (const m of decoder.push(chunk)) onMsgHandlers.forEach((h) => h(m as S2C));
      });
      socket.on('close', () => onCloseHandlers.forEach((h) => h()));
      socket.on('error', () => {});
      resolve({
        send: (m) => socket.write(encode(m)),
        onMessage: (h) => onMsgHandlers.push(h),
        onClose: (h) => onCloseHandlers.push(h),
        close: () => socket.end(),
      });
    });
    socket.once('error', (err) => reject(err));
  });
}

// ─── render: menus ──────────────────────────────────────────────────────────
function mainMenuFrame(error: string | null): string {
  const buf: string[] = [CLEAR, '\n\n'];
  buf.push(panelTop('CHING · MULTIPLAYER') + '\n');
  buf.push(panelLine('') + '\n');
  buf.push(panelLine('  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'C' + RESET + fg(P_LIME) + ']reate room' + RESET) + '\n');
  buf.push(panelLine('  ' + fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'J' + RESET + fg(P_LIME) + ']oin by code' + RESET) + '\n');
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
type Term = {
  setup: () => void;
  teardown: () => void;
  draw: (s: string) => void;
  showCursor: () => void;
  hideCursor: () => void;
  waitKey: () => Promise<string>;
  delay: (ms: number) => Promise<void>;
};

const realTerm: Term = {
  setup: setupTerm,
  teardown: teardownTerm,
  draw: drawFrame,
  showCursor,
  hideCursor,
  waitKey,
  delay,
};

export type ClientHandle = { shutdown: (code: number) => void };

export async function runClient(
  conn: Conn,
  term: Term,
  opts: { sockPath: string; sessionFile: string; name: string; token: string | null },
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

  function exit(code: number): void {
    if (exited) return;
    exited = true;
    exitCode = code;
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
        saveToken(opts.sessionFile, opts.sockPath, m.token);
        if (m.seatHint) {
          menuKey = 'lobby';
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
        if (menuKey === 'game') redrawGame();
      } else if (m.t === 'ERROR') {
        lastError = m.code + ': ' + m.message;
        if (menuKey === 'menu') term.draw(mainMenuFrame(lastError));
        else if (menuKey === 'lobby' && lobbyData) {
          term.draw(lobbyFrame({ ...lobbyData, footer: lobbyFooterFor() }));
        }
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

  term.draw(mainMenuFrame(null));

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
        const code = await readCode(term);
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
        const seat = await readSeatNumber(term, lb.seats.length);
        if (seat !== null) conn.send({ v: 1, t: 'REMOVE_SEAT', seat });
      } else if (k === 's' && lb.mySeat === lb.host) {
        conn.send({ v: 1, t: 'START' });
      } else if (k === 'l') {
        conn.send({ v: 1, t: 'LEAVE' });
      }
      term.draw(lobbyFrame({ ...lb, footer: lobbyFooterFor() }));
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

const CODE_CHARS = new Set('ABCDEFGHJKMNPQRSTUVWXYZ23456789'.split(''));
async function readCode(term: Term): Promise<string | null> {
  let buf = '';
  term.draw(ESC + '?25h'); // show cursor
  while (buf.length < 4) {
    term.draw('\r   ' + fg(P_LIME) + '> code: ' + fg(TEXT) + buf + fg(DIM_TEXT) + '_'.repeat(4 - buf.length) + RESET);
    const k = (await term.waitKey()).toUpperCase();
    if (k === '\r' || k === '\n') break;
    if (k === 'Q' || k === '\x1b') return null;
    if (k === '\x7f' || k === '\b') {
      buf = buf.slice(0, -1);
      continue;
    }
    if (CODE_CHARS.has(k)) buf += k;
  }
  term.draw(ESC + '?25l');
  return buf.length === 4 ? buf : null;
}

async function readSeatNumber(term: Term, max: number): Promise<number | null> {
  term.draw('\r   ' + fg(P_LIME) + '> seat # (1-' + max + '): ' + RESET);
  const k = await term.waitKey();
  const n = Number(k);
  if (Number.isInteger(n) && n >= 1 && n <= max) return n - 1;
  return null;
}

// ─── entry point ────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const sockPath = process.env.CHING_SOCK ?? DEFAULT_SOCK;
  const sessionFile = resolveSessionFile();
  const sess = loadSession(sessionFile, sockPath);

  let conn: Conn;
  try {
    conn = await connectSocket(sockPath);
  } catch (err) {
    console.error('could not connect to daemon at ' + sockPath);
    console.error('start it with: npm run daemon');
    process.exit(1);
    return;
  }

  const sigHandler = (sig: string) => {
    teardownTerm();
    conn.close();
    void sig;
    process.exit(0);
  };
  process.on('SIGINT', () => sigHandler('SIGINT'));
  process.on('SIGTERM', () => sigHandler('SIGTERM'));

  const code = await runClient(conn, realTerm, {
    sockPath,
    sessionFile,
    name: sess.name,
    token: sess.token,
  });
  process.exit(code);
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
