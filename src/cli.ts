// CHING terminal renderer. Swappable shell. Reads engine state, sends
// engine actions. Game rules live in the engine, not here.

import {
  COIN,
  initialState,
  step,
  tileCoins,
  type Action,
  type Face,
  type Rng,
  type State,
} from './engine.js';
import { decide, type Difficulty } from './ai.js';

// ─── ansi palette (80s green CRT + accents) ─────────────────────────────────
const A = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  blink: '\x1b[5m',
  invert: '\x1b[7m',
  green: '\x1b[92m',
  yellow: '\x1b[93m',
  red: '\x1b[91m',
  cyan: '\x1b[96m',
  magenta: '\x1b[95m',
  white: '\x1b[97m',
  gray: '\x1b[90m',
  clear: '\x1b[2J\x1b[H',
  hideCursor: '\x1b[?25l',
  showCursor: '\x1b[?25h',
};
const BELL = '\x07';

const HUMAN = 0;
const AI = 1;
const DEFAULT_DISCIPLINE = 0.6;

const ROLL_REVEAL_MS = 90;
const AI_THINK_MS = 380;
const FLASH_MS = 110;

// ─── tty helpers ────────────────────────────────────────────────────────────
function out(s: string): void {
  process.stdout.write(s);
}

function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

let inputBuf = '';
const inputWaiters: Array<(c: string) => void> = [];

function flushInput(): void {
  while (inputWaiters.length > 0 && inputBuf.length > 0) {
    const cb = inputWaiters.shift()!;
    const ch = inputBuf[0];
    inputBuf = inputBuf.slice(1);
    cb(ch);
  }
}

function setupInput(): void {
  if (process.stdin.isTTY) process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk: string) => {
    inputBuf += chunk;
    flushInput();
  });
  // Treat ^C and EOF like quit.
  process.stdin.on('end', () => {
    inputBuf += 'q';
    flushInput();
  });
}

function teardownInput(): void {
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  process.stdin.pause();
  out(A.showCursor + A.reset);
}

function waitKey(): Promise<string> {
  return new Promise((resolve) => {
    inputWaiters.push(resolve);
    flushInput();
  });
}

async function typewrite(text: string, msPerChar = 8): Promise<void> {
  for (const ch of text) {
    out(ch);
    if (msPerChar > 0) await delay(msPerChar);
  }
}

// ─── boot/microloader ───────────────────────────────────────────────────────
async function boot(): Promise<void> {
  out(A.clear + A.hideCursor + A.green);
  await typewrite('> BOOT...\n', 14);
  await delay(160);
  const lines: Array<[string, number]> = [
    ['MICROLOADER v2.1', 90],
    ['RAM CHECK', 50],
    ['DICE MATRIX 8x6', 70],
    ['COIN PROTOCOL', 80],
    ['TILE BANK 16/16', 60],
  ];
  for (const [label, ms] of lines) {
    out('> ' + label);
    const dots = 36 - label.length;
    for (let i = 0; i < dots; i++) {
      out('.');
      await delay(ms / dots);
    }
    out(A.yellow + 'OK' + A.green + '\n');
    await delay(70);
  }
  out('> READY.\n\n');
  await delay(260);

  const banner = [
    '    ██████  ██   ██  ██  ███   ██   ██████  ',
    '   ██       ██   ██  ██  ████  ██  ██       ',
    '   ██       ███████  ██  ██ ██ ██  ██   ███ ',
    '   ██       ██   ██  ██  ██  ████  ██    ██ ',
    '    ██████  ██   ██  ██  ██   ██    ██████  ',
  ];
  out(A.yellow + A.bold);
  for (const line of banner) out(line + '\n');
  out(A.reset + A.green + '\n');
  out('   push your luck  •  collect  •  steal  •  ');
  out(A.yellow + A.bold + 'CHING!' + A.reset + A.green + '\n\n');
  out(A.dim + '   [any key to start]' + A.reset);
  await waitKey();
}

// ─── cell renderers ─────────────────────────────────────────────────────────
const FACE_GLYPH: Record<Face, string> = {
  1: '1',
  2: '2',
  3: '3',
  4: '4',
  5: '5',
  6: '$',
};

function dieCell(f: Face, glint = false): string {
  const isCoin = f === COIN;
  if (isCoin) {
    return (
      A.yellow + A.bold + '[' + (glint ? A.blink : '') + '$' + A.reset + A.yellow + A.bold + ']' + A.reset
    );
  }
  return A.white + '[' + FACE_GLYPH[f] + ']' + A.reset;
}

function tileCell(t: number): string {
  const c = tileCoins(t);
  const color = c === 1 ? A.gray : c === 2 ? A.cyan : c === 3 ? A.magenta : A.yellow;
  const stars = '★'.repeat(c);
  return color + '[' + t + ' ' + stars + ']' + A.reset;
}

function row(cells: string[], indent = '   '): string {
  return indent + cells.join(' ');
}

function setAsideSum(state: State): number {
  return state.setAside.reduce((acc, f) => acc + (f === COIN ? 5 : f), 0);
}

function pickedSummary(state: State): string {
  if (state.pickedFaces.length === 0) return A.dim + '(none)' + A.reset;
  return state.pickedFaces
    .map((f) => (f === COIN ? A.yellow + '$' + A.reset : A.white + String(f) + A.reset))
    .join(' ');
}

const LABEL_WIDTH = 10; // keeps the tile column aligned across players

function playerLine(label: string, color: string, p: State['players'][number]): string {
  const padded = label.padEnd(LABEL_WIDTH, ' ');
  const coins = p.tiles.reduce((s, t) => s + tileCoins(t), 0);
  const tiles =
    p.tiles.length === 0
      ? A.dim + '(none)' + A.reset
      : p.tiles.map((t) => tileCell(t)).join(' ');
  return (
    color + A.bold + padded + A.reset + '  ' + tiles + '   ' + A.dim + 'coins:' + A.reset + ' ' +
    A.yellow + A.bold + coins + A.reset
  );
}

// ─── full-frame render ──────────────────────────────────────────────────────
function render(state: State, opts: { aiDiscipline: number; status?: string } = { aiDiscipline: DEFAULT_DISCIPLINE }): void {
  out(A.clear);
  const inner = 66;
  const left = '  CHING v0.1';
  const right = '8-BIT TERMINAL EDITION  ';
  const gap = ' '.repeat(Math.max(1, inner - left.length - right.length));
  out(A.green + A.bold + '╔' + '═'.repeat(inner) + '╗\n');
  out('║' + left + gap + right + '║\n');
  out('╚' + '═'.repeat(inner) + '╝' + A.reset + '\n\n');

  out(A.green + A.bold + ' CENTER TILES' + A.reset + A.dim + '  (★ = coins per tile)' + A.reset + '\n');
  if (state.centerTiles.length === 0) {
    out('   ' + A.dim + '(empty)' + A.reset + '\n');
  } else {
    const cells = state.centerTiles.map(tileCell);
    for (let i = 0; i < cells.length; i += 8) {
      out(row(cells.slice(i, i + 8)) + '\n');
    }
  }
  out('\n');

  out(playerLine('YOU', A.cyan, state.players[HUMAN]) + '\n');
  out(
    playerLine('AI (' + opts.aiDiscipline.toFixed(1) + ')', A.magenta, state.players[AI]) + '\n\n',
  );

  const whoColor = state.current === HUMAN ? A.cyan : A.magenta;
  const whoName = state.current === HUMAN ? 'YOU' : 'AI';
  out(A.green + ' TURN: ' + whoColor + A.bold + whoName + A.reset + '\n');

  if (state.rolled.length > 0) {
    out('   ' + A.dim + 'rolled    ' + A.reset + state.rolled.map((f) => dieCell(f, true)).join(' ') + '\n');
  } else {
    out('   ' + A.dim + 'rolled    ' + A.reset + A.dim + '(none yet)' + A.reset + '\n');
  }
  const sum = setAsideSum(state);
  const hasCoin = state.setAside.includes(COIN);
  const sumColor = hasCoin ? A.yellow : A.red;
  out(
    '   ' +
      A.dim + 'set aside ' + A.reset +
      (state.setAside.length === 0
        ? A.dim + '(none)' + A.reset
        : state.setAside.map((f) => dieCell(f)).join(' ')) +
      '   ' + A.dim + 'sum:' + A.reset + ' ' + sumColor + A.bold + sum + A.reset +
      (hasCoin ? A.green + ' ✓coin' + A.reset : A.red + ' no coin' + A.reset) + '\n',
  );
  out('   ' + A.dim + 'picked    ' + A.reset + pickedSummary(state) + '   ' + A.dim + 'dice in hand:' + A.reset + ' ' + state.diceInHand + '\n');

  if (opts.status) {
    out('\n   ' + opts.status + '\n');
  }
}

// ─── effects: ka-ching, bust, steal banners ─────────────────────────────────
async function flashBanner(text: string, color: string, beep: boolean): Promise<void> {
  if (beep) out(BELL);
  for (let i = 0; i < 3; i++) {
    out('\n   ' + color + A.bold + A.invert + ' ' + text + ' ' + A.reset);
    await delay(FLASH_MS);
    out('\r   ' + ' '.repeat(text.length + 2) + '\r');
    await delay(FLASH_MS);
  }
  out('\n   ' + color + A.bold + text + A.reset + '\n');
}

async function effects(prev: State, next: State, opts: { aiDiscipline: number }): Promise<void> {
  // Only react when the turn actually ended.
  if (next.current === prev.current && next.phase !== 'over') return;

  const actor = prev.current;
  const prevTiles = prev.players[actor].tiles.length;
  const nextTiles = next.players[actor].tiles.length;
  const prevCenter = prev.centerTiles.length;
  const nextCenter = next.centerTiles.length;
  const sum = setAsideSum(prev);

  if (nextTiles > prevTiles) {
    if (nextCenter < prevCenter) {
      const tile = next.players[actor].tiles[next.players[actor].tiles.length - 1];
      render(next, { aiDiscipline: opts.aiDiscipline });
      await flashBanner('★  K A · C H I N G !  ★   banked [' + tile + ' ' + '★'.repeat(tileCoins(tile)) + ']', A.yellow, true);
    } else {
      const tile = next.players[actor].tiles[next.players[actor].tiles.length - 1];
      render(next, { aiDiscipline: opts.aiDiscipline });
      await flashBanner('▶  S T E A L !  ◀   took [' + tile + ' ' + '★'.repeat(tileCoins(tile)) + ']', A.magenta, true);
    }
  } else if (nextTiles < prevTiles || nextCenter < prevCenter || (prev.setAside.length > 0 && nextCenter > prevCenter)) {
    render(next, { aiDiscipline: opts.aiDiscipline });
    await flashBanner('✗  B U S T !  ✗   sum was ' + sum, A.red, false);
  }
}

// ─── human input ────────────────────────────────────────────────────────────
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
    const keys = faces.map((f) => (f === COIN ? A.yellow + 'C' + A.reset : A.white + String(f) + A.reset)).join(' ');
    return A.green + '   > pick a face [' + keys + A.green + ']  ' + A.dim + '(Q to quit) ' + A.reset;
  }
  // phase === 'roll'
  const canStop = state.setAside.length > 0;
  const choices = [A.green + '[' + A.bold + 'R' + A.reset + A.green + ']oll'];
  if (canStop) choices.push(A.green + '[' + A.bold + 'S' + A.reset + A.green + ']top');
  choices.push(A.dim + '[Q]uit' + A.reset);
  return A.green + '   > ' + choices.join('  ') + ' ' + A.reset;
}

async function readKeyMatching(predicate: (k: string) => boolean): Promise<string> {
  for (;;) {
    const raw = await waitKey();
    const k = raw.toLowerCase();
    if (k === '' || k === 'q') return 'q'; // ^C or Q
    if (predicate(k)) return k;
  }
}

async function promptHuman(state: State): Promise<Action | 'QUIT'> {
  out(promptText(state));
  out(A.showCursor);
  if (state.phase === 'pick') {
    const valid = validPickFaces(state);
    const k = await readKeyMatching((k) => {
      if (k === 'c' || k === '$') return valid.includes(COIN);
      const n = Number(k);
      return Number.isInteger(n) && n >= 1 && n <= 5 && valid.includes(n as Face);
    });
    out(A.hideCursor);
    if (k === 'q') return 'QUIT';
    const face: Face = k === 'c' || k === '$' ? COIN : (Number(k) as Face);
    return { type: 'PICK', face };
  }
  const canStop = state.setAside.length > 0;
  const k = await readKeyMatching((k) => k === 'r' || (canStop && k === 's'));
  out(A.hideCursor);
  if (k === 'q') return 'QUIT';
  return k === 'r' ? { type: 'ROLL' } : { type: 'STOP' };
}

// ─── ai turn pacing ─────────────────────────────────────────────────────────
async function aiTurnAction(state: State, ai: Difficulty): Promise<Action> {
  // Brief "thinking" beat so the human can track what the AI saw.
  await delay(AI_THINK_MS);
  return decide(state, ai);
}

// ─── roll reveal animation ──────────────────────────────────────────────────
async function animateRoll(before: State, after: State, opts: { aiDiscipline: number }): Promise<void> {
  if (after.rolled.length === 0) return; // bust on roll, nothing to reveal
  const partial: State = { ...before, rolled: [], phase: 'pick' };
  render(partial, { aiDiscipline: opts.aiDiscipline, status: A.dim + 'rolling…' + A.reset });
  for (let i = 0; i < after.rolled.length; i++) {
    const visible = after.rolled.slice(0, i + 1);
    const snap: State = { ...partial, rolled: visible };
    render(snap, { aiDiscipline: opts.aiDiscipline, status: A.dim + 'rolling…' + A.reset });
    await delay(ROLL_REVEAL_MS);
  }
}

// ─── game over screen ───────────────────────────────────────────────────────
function renderGameOver(state: State, aiDiscipline: number): void {
  const youCoins = state.players[HUMAN].tiles.reduce((s, t) => s + tileCoins(t), 0);
  const aiCoins = state.players[AI].tiles.reduce((s, t) => s + tileCoins(t), 0);
  out('\n');
  const headColor = youCoins > aiCoins ? A.yellow : youCoins < aiCoins ? A.red : A.cyan;
  const heading =
    youCoins > aiCoins
      ? '═══  YOU WIN  ═══'
      : youCoins < aiCoins
        ? '═══  AI WINS  ═══'
        : '═══  TIE GAME  ═══';
  out('   ' + headColor + A.bold + heading + A.reset + '\n');
  out('   ' + A.cyan + 'YOU       ' + A.reset + youCoins + ' coins   ' + state.players[HUMAN].tiles.map(tileCell).join(' ') + '\n');
  out('   ' + A.magenta + 'AI (' + aiDiscipline.toFixed(1) + ') ' + A.reset + aiCoins + ' coins   ' + state.players[AI].tiles.map(tileCell).join(' ') + '\n\n');
  out(A.dim + '   [any key to exit]' + A.reset);
}

// ─── main loop ──────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const aiDiscipline = parseDiscipline(process.argv.slice(2)) ?? DEFAULT_DISCIPLINE;
  const ai: Difficulty = { discipline: aiDiscipline };

  setupInput();
  await boot();

  // Math.random is fine here: rules live in the engine, this is just the shell.
  const rng: Rng = Math.random;
  let state = initialState(['YOU', 'AI']);

  while (state.phase !== 'over') {
    render(state, { aiDiscipline });

    let action: Action;
    if (state.current === HUMAN) {
      const choice = await promptHuman(state);
      if (choice === 'QUIT') {
        out('\n' + A.dim + '   quit.' + A.reset + '\n');
        teardownInput();
        return;
      }
      action = choice;
    } else {
      out('\n   ' + A.dim + 'AI thinking…' + A.reset);
      action = await aiTurnAction(state, ai);
    }

    const before = state;
    const after = step(state, action, rng);

    if (action.type === 'ROLL' && after.rolled.length > 0) {
      await animateRoll(before, after, { aiDiscipline });
    }

    state = after;
    await effects(before, state, { aiDiscipline });
  }

  render(state, { aiDiscipline });
  renderGameOver(state, aiDiscipline);
  await waitKey();
  teardownInput();
}

function parseDiscipline(args: string[]): number | null {
  for (const a of args) {
    const m = /^--discipline=(\d*\.?\d+)$/.exec(a);
    if (m) {
      const n = Number(m[1]);
      if (n >= 0 && n <= 1) return n;
    }
  }
  return null;
}

main().catch((err) => {
  teardownInput();
  // eslint-disable-next-line no-console
  console.error(err);
  process.exit(1);
});
