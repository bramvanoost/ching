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

// ─── 256-color CRT palette ──────────────────────────────────────────────────
const ESC = '\x1b[';
const fg = (n: number): string => ESC + '38;5;' + n + 'm';
const RESET = ESC + '0m';
const BOLD = ESC + '1m';
const DIM = ESC + '2m';
const INVERT = ESC + '7m';
const CLEAR = ESC + 'H' + ESC + '2J';
const HIDE_CURSOR = ESC + '?25l';
const SHOW_CURSOR = ESC + '?25h';
const ENTER_ALT = ESC + '?1049h';
const EXIT_ALT = ESC + '?1049l';
const BELL = '\x07';

// Phosphor green (dim → neon → lime)
const P_DARK = 22;
const P_DIM = 28;
const P_MED = 34;
const P_BR = 40;
const P_NEON = 46;
const P_LIME = 82;
const P_LIME2 = 118;
const P_LIME3 = 154;
const PHOSPHOR_GRADIENT = [
  P_DARK,
  P_DIM,
  P_MED,
  P_BR,
  P_NEON,
  P_LIME,
  P_LIME2,
  P_LIME3,
  P_LIME2,
  P_LIME,
  P_NEON,
  P_BR,
  P_MED,
  P_DIM,
  P_DARK,
];

// Amber CRT (the other classic mainframe tone)
const A_DIM = 130;
const A_MED = 178;
const A_BR = 214;
const A_GLINT = 220;

// Cool accents
const Cy_BR = 51;
const Mg_BR = 207;

// Tile tiers
const TIER1 = 246;
const TIER2 = 38;
const TIER3 = 135;
const TIER4 = 214;

// Surfaces
const TEXT = 252;
const DIM_TEXT = 244;
const SHADOW = 235;
const RED = 196;

// ─── game wiring ────────────────────────────────────────────────────────────
const HUMAN = 0;
const AI = 1;
const DEFAULT_DISCIPLINE = 0.6;

const INNER = 66;
const SHADOW_CHAR = '▒';
const LABEL_WIDTH = 10;

const ROLL_REVEAL_MS = 70;
const COIN_SPIN_MS = 55;
const COIN_SPIN_FRAMES = 4;
const COIN_GLINT_MS = 100;
const AI_THINK_MS = 380;
const FLASH_MS = 110;

const COIN_SPIN: readonly string[] = ['◐', '◓', '◑', '◒'];
const COIN_STATIC = '✦';

// ─── tty plumbing ───────────────────────────────────────────────────────────
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
  process.stdin.on('end', () => {
    inputBuf += 'q';
    flushInput();
  });
  // Alternate screen buffer: no scrollback pollution, no spillover.
  out(ENTER_ALT + HIDE_CURSOR);
}

function teardownInput(): void {
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  process.stdin.pause();
  out(SHOW_CURSOR + RESET + EXIT_ALT);
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

// ─── width-aware helpers ────────────────────────────────────────────────────
function visibleLen(s: string): number {
  // Strip CSI sequences so padding math sees actual glyph counts.
  return s.replace(/\x1b\[[\d;?]*[A-Za-z]/g, '').length;
}

// ─── panel primitives (bevel + drop shadow) ─────────────────────────────────
function panelTop(label?: string, inner = INNER): string {
  if (label) {
    const tag = ' ' + label + ' ';
    const tagLen = visibleLen(tag);
    const leftFill = 3;
    const rightFill = Math.max(1, inner - leftFill - tagLen);
    return (
      fg(P_NEON) + BOLD + '╔' + '═'.repeat(leftFill) + RESET +
      fg(P_LIME2) + BOLD + tag + RESET +
      fg(P_NEON) + BOLD + '═'.repeat(rightFill) + '╗' + RESET
    );
  }
  return fg(P_NEON) + BOLD + '╔' + '═'.repeat(inner) + '╗' + RESET;
}

function panelLine(content: string, inner = INNER): string {
  const vis = visibleLen(content);
  const pad = ' '.repeat(Math.max(0, inner - vis));
  return (
    fg(P_BR) + '║' + RESET + content + pad +
    fg(P_BR) + '║' + RESET +
    fg(SHADOW) + SHADOW_CHAR + RESET
  );
}

function panelBottom(inner = INNER): string {
  const bot =
    fg(P_DIM) + '╚' + '═'.repeat(inner) + '╝' + RESET +
    fg(SHADOW) + SHADOW_CHAR + RESET;
  const shadowRow = ' ' + fg(SHADOW) + SHADOW_CHAR.repeat(inner + 2) + RESET;
  return bot + '\n' + shadowRow;
}

// ─── die / tile cells ───────────────────────────────────────────────────────
function tileCell(t: number): string {
  const c = tileCoins(t);
  const color = c === 1 ? TIER1 : c === 2 ? TIER2 : c === 3 ? TIER3 : TIER4;
  const stars = '★'.repeat(c);
  return fg(color) + '[' + t + ' ' + stars + ']' + RESET;
}

function coinCell(spinFrame?: number, glint?: boolean): string {
  if (glint) {
    return (
      fg(A_GLINT) + BOLD + '[' + INVERT + ' ' + COIN_STATIC + ' ' + RESET +
      fg(A_GLINT) + BOLD + ']' + RESET
    );
  }
  if (spinFrame !== undefined) {
    const g = COIN_SPIN[spinFrame % COIN_SPIN.length];
    return (
      fg(A_MED) + '[' + fg(A_BR) + BOLD + g + RESET + fg(A_MED) + ']' + RESET
    );
  }
  // Settled coin: a quiet amber star, so the signature object always reads.
  return (
    fg(A_MED) + '[' + fg(A_GLINT) + BOLD + COIN_STATIC + RESET +
    fg(A_MED) + ']' + RESET
  );
}

function dieCell(f: Face, spinFrame?: number, glint?: boolean): string {
  if (f === COIN) return coinCell(spinFrame, glint);
  return fg(DIM_TEXT) + '[' + fg(TEXT) + String(f) + fg(DIM_TEXT) + ']' + RESET;
}

function setAsideSum(state: State): number {
  return state.setAside.reduce((acc, f) => acc + (f === COIN ? 5 : f), 0);
}

function pickedSummary(state: State): string {
  if (state.pickedFaces.length === 0) return fg(DIM_TEXT) + '(none)' + RESET;
  return state.pickedFaces
    .map((f) =>
      f === COIN
        ? fg(A_GLINT) + BOLD + COIN_STATIC + RESET
        : fg(TEXT) + String(f) + RESET,
    )
    .join(' ');
}

function playerLineContent(
  label: string,
  color: number,
  p: State['players'][number],
): string {
  const padded = label.padEnd(LABEL_WIDTH, ' ');
  const coins = p.tiles.reduce((s, t) => s + tileCoins(t), 0);
  const tiles =
    p.tiles.length === 0
      ? fg(DIM_TEXT) + '(none)' + RESET
      : p.tiles.map(tileCell).join(' ');
  return (
    fg(color) + BOLD + padded + RESET + '  ' + tiles + '   ' +
    fg(DIM_TEXT) + 'coins:' + RESET + ' ' +
    fg(A_GLINT) + BOLD + coins + RESET
  );
}

function rolledLine(state: State, opts: RenderOpts): string {
  if (state.rolled.length === 0) {
    return fg(DIM_TEXT) + '(none yet)' + RESET;
  }
  return state.rolled
    .map((f, i) => {
      if (i === opts.spinIdx) {
        return dieCell(f, opts.spinFrame, opts.spinGlint);
      }
      return dieCell(f);
    })
    .join(' ');
}

// ─── full-frame render ──────────────────────────────────────────────────────
type RenderOpts = {
  aiDiscipline: number;
  // Single line shown below all panels (prompt, AI think, animation hint).
  // No trailing newline: the cursor parks here so input/spinning stays inline.
  footer?: string;
  spinIdx?: number;
  spinFrame?: number;
  spinGlint?: boolean;
};

function render(state: State, opts: RenderOpts): void {
  out(CLEAR);

  // Header.
  const titleLeft = fg(P_LIME2) + BOLD + 'CHING' + RESET + fg(P_MED) + ' v0.1' + RESET;
  const titleRight = fg(A_MED) + '8-BIT TERMINAL EDITION' + RESET;
  const gap = Math.max(1, INNER - 4 - visibleLen(titleLeft) - visibleLen(titleRight));
  out(panelTop() + '\n');
  out(panelLine('  ' + titleLeft + ' '.repeat(gap) + titleRight + '  ') + '\n');
  out(panelBottom() + '\n');

  // Center tiles.
  out(panelTop('CENTER TILES  ' + fg(DIM_TEXT) + '(★ = coins per tile)' + RESET + fg(P_LIME2) + BOLD) + '\n');
  if (state.centerTiles.length === 0) {
    out(panelLine('  ' + fg(DIM_TEXT) + '(empty)' + RESET) + '\n');
  } else {
    const cells = state.centerTiles.map(tileCell);
    // 6 per row: even a row of all 4-star tiles fits inside INNER=66.
    for (let i = 0; i < cells.length; i += 6) {
      out(panelLine('  ' + cells.slice(i, i + 6).join(' ')) + '\n');
    }
  }
  out(panelBottom() + '\n');

  // Players.
  out(panelTop('PLAYERS') + '\n');
  out(panelLine('  ' + playerLineContent('YOU', Cy_BR, state.players[HUMAN])) + '\n');
  out(
    panelLine(
      '  ' +
        playerLineContent(
          'AI (' + opts.aiDiscipline.toFixed(1) + ')',
          Mg_BR,
          state.players[AI],
        ),
    ) + '\n',
  );
  out(panelBottom() + '\n');

  // Current turn.
  const turnName = state.current === HUMAN ? 'YOU' : 'AI';
  const turnColor = state.current === HUMAN ? Cy_BR : Mg_BR;
  out(
    panelTop(
      'TURN: ' + fg(turnColor) + BOLD + turnName + RESET + fg(P_LIME2) + BOLD,
    ) + '\n',
  );

  out(
    panelLine(
      '  ' + fg(DIM_TEXT) + 'rolled    ' + RESET + rolledLine(state, opts),
    ) + '\n',
  );

  const sum = setAsideSum(state);
  const hasCoin = state.setAside.includes(COIN);
  const sumColor = hasCoin ? A_GLINT : RED;
  const coinFlag = hasCoin
    ? fg(P_NEON) + ' ✓coin' + RESET
    : fg(RED) + ' no coin' + RESET;
  const setAsideStr =
    state.setAside.length === 0
      ? fg(DIM_TEXT) + '(none)' + RESET
      : state.setAside.map((f) => dieCell(f)).join(' ');
  out(
    panelLine(
      '  ' + fg(DIM_TEXT) + 'set aside ' + RESET + setAsideStr + '   ' +
        fg(DIM_TEXT) + 'sum:' + RESET + ' ' +
        fg(sumColor) + BOLD + sum + RESET + coinFlag,
    ) + '\n',
  );
  out(
    panelLine(
      '  ' + fg(DIM_TEXT) + 'picked    ' + RESET + pickedSummary(state) + '   ' +
        fg(DIM_TEXT) + 'dice in hand:' + RESET + ' ' + state.diceInHand,
    ) + '\n',
  );
  out(panelBottom() + '\n');

  // Footer line, drawn into the same frame so nothing scrolls below.
  if (opts.footer) {
    out('   ' + opts.footer);
  }
}

// ─── boot/microloader with phosphor gradient ────────────────────────────────
async function boot(): Promise<void> {
  out(CLEAR + HIDE_CURSOR + fg(P_BR));
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
    out(fg(P_MED) + '> ' + RESET + fg(P_BR) + label + RESET);
    const dots = 36 - label.length;
    for (let i = 0; i < dots; i++) {
      out(fg(P_DIM) + '.' + RESET);
      await delay(ms / dots);
    }
    out(fg(A_GLINT) + BOLD + 'OK' + RESET + '\n');
    await delay(70);
  }
  out(fg(P_MED) + '> ' + fg(P_LIME2) + BOLD + 'READY.' + RESET + '\n\n');
  await delay(260);

  const banner = [
    '    ██████  ██   ██  ██  ███   ██   ██████  ',
    '   ██       ██   ██  ██  ████  ██  ██       ',
    '   ██       ███████  ██  ██ ██ ██  ██   ███ ',
    '   ██       ██   ██  ██  ██  ████  ██    ██ ',
    '    ██████  ██   ██  ██  ██   ██    ██████  ',
  ];
  out(gradientBanner(banner));
  out(
    '\n   ' + fg(P_BR) + 'push your luck  •  collect  •  steal  •  ' +
    fg(A_GLINT) + BOLD + 'CHING!' + RESET + '\n\n',
  );
  out(fg(DIM_TEXT) + '   [any key to start]' + RESET);
  await waitKey();
}

function gradientBanner(lines: string[]): string {
  const width = Math.max(...lines.map((l) => l.length));
  let buf = '';
  for (const line of lines) {
    for (let col = 0; col < line.length; col++) {
      const ch = line[col];
      if (ch === ' ') {
        buf += ' ';
      } else {
        const i = Math.min(
          PHOSPHOR_GRADIENT.length - 1,
          Math.floor((col / width) * PHOSPHOR_GRADIENT.length),
        );
        buf += fg(PHOSPHOR_GRADIENT[i]) + BOLD + ch + RESET;
      }
    }
    buf += '\n';
  }
  return buf;
}

// ─── effects: ka-ching / bust / steal ───────────────────────────────────────
async function flashBanner(text: string, color: number, beep: boolean): Promise<void> {
  if (beep) out(BELL);
  // Flash in place on the footer row so we never grow the frame.
  const onText = '   ' + fg(color) + BOLD + INVERT + ' ' + text + ' ' + RESET;
  const blank = '   ' + ' '.repeat(visibleLen(text) + 2);
  const settle = '   ' + fg(color) + BOLD + text + RESET;
  for (let i = 0; i < 3; i++) {
    out('\r' + onText);
    await delay(FLASH_MS);
    out('\r' + blank);
    await delay(FLASH_MS);
  }
  out('\r' + settle);
  await delay(FLASH_MS * 2);
}

async function effects(prev: State, next: State, opts: RenderOpts): Promise<void> {
  if (next.current === prev.current && next.phase !== 'over') return;
  const actor = prev.current;
  const prevTiles = prev.players[actor].tiles.length;
  const nextTiles = next.players[actor].tiles.length;
  const prevCenter = prev.centerTiles.length;
  const nextCenter = next.centerTiles.length;
  const sum = setAsideSum(prev);

  if (nextTiles > prevTiles) {
    const tile = next.players[actor].tiles[next.players[actor].tiles.length - 1];
    const tileBadge = '[' + tile + ' ' + '★'.repeat(tileCoins(tile)) + ']';
    if (nextCenter < prevCenter) {
      render(next, opts);
      await flashBanner('★  K A · C H I N G !  ★   banked ' + tileBadge, A_GLINT, true);
    } else {
      render(next, opts);
      await flashBanner('▶  S T E A L !  ◀   took ' + tileBadge, Mg_BR, true);
    }
  } else if (
    nextTiles < prevTiles ||
    nextCenter < prevCenter ||
    (prev.setAside.length > 0 && nextCenter >= prevCenter)
  ) {
    render(next, opts);
    await flashBanner('✗  B U S T !  ✗   sum was ' + sum, RED, false);
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
  // Indent is provided by render()'s footer prefix; promptText starts at "> ".
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
  if (canStop) {
    choices.push(fg(P_LIME) + '[' + fg(A_GLINT) + BOLD + 'S' + RESET + fg(P_LIME) + ']top' + RESET);
  }
  choices.push(fg(DIM_TEXT) + '[Q]uit' + RESET);
  return fg(P_LIME) + '> ' + choices.join('  ') + ' ' + RESET;
}

async function readKeyMatching(predicate: (k: string) => boolean): Promise<string> {
  for (;;) {
    const raw = await waitKey();
    const k = raw.toLowerCase();
    if (k === '' || k === 'q') return 'q';
    if (predicate(k)) return k;
  }
}

async function promptHuman(state: State): Promise<Action | 'QUIT'> {
  // The prompt text is drawn by render() as the footer; we just wait for a key.
  if (state.phase === 'pick') {
    const valid = validPickFaces(state);
    const k = await readKeyMatching((k) => {
      if (k === 'c' || k === '$') return valid.includes(COIN);
      const n = Number(k);
      return Number.isInteger(n) && n >= 1 && n <= 5 && valid.includes(n as Face);
    });
    if (k === 'q') return 'QUIT';
    const face: Face = k === 'c' || k === '$' ? COIN : (Number(k) as Face);
    return { type: 'PICK', face };
  }
  const canStop = state.setAside.length > 0;
  const k = await readKeyMatching((k) => k === 'r' || (canStop && k === 's'));
  if (k === 'q') return 'QUIT';
  return k === 'r' ? { type: 'ROLL' } : { type: 'STOP' };
}

// ─── ai pacing ──────────────────────────────────────────────────────────────
async function aiTurnAction(state: State, ai: Difficulty): Promise<Action> {
  await delay(AI_THINK_MS);
  return decide(state, ai);
}

// ─── roll reveal with spinning coins ────────────────────────────────────────
async function animateRoll(before: State, after: State, opts: RenderOpts): Promise<void> {
  if (after.rolled.length === 0) return;
  const partial: State = { ...before, rolled: [], phase: 'pick' };
  const footer = fg(DIM_TEXT) + 'rolling…' + RESET;

  render(partial, { ...opts, footer });
  await delay(ROLL_REVEAL_MS);

  for (let i = 0; i < after.rolled.length; i++) {
    const newDie = after.rolled[i];
    const visible = after.rolled.slice(0, i + 1);
    const snap: State = { ...partial, rolled: visible };

    if (newDie === COIN) {
      for (let frame = 0; frame < COIN_SPIN_FRAMES; frame++) {
        render(snap, { ...opts, footer, spinIdx: i, spinFrame: frame });
        await delay(COIN_SPIN_MS);
      }
      render(snap, { ...opts, footer, spinIdx: i, spinGlint: true });
      await delay(COIN_GLINT_MS);
    } else {
      render(snap, { ...opts, footer });
      await delay(ROLL_REVEAL_MS);
    }
  }
}

// ─── game over ──────────────────────────────────────────────────────────────
function renderGameOver(state: State, aiDiscipline: number): void {
  const youCoins = state.players[HUMAN].tiles.reduce((s, t) => s + tileCoins(t), 0);
  const aiCoins = state.players[AI].tiles.reduce((s, t) => s + tileCoins(t), 0);
  const headColor = youCoins > aiCoins ? A_GLINT : youCoins < aiCoins ? RED : Cy_BR;
  const heading =
    youCoins > aiCoins
      ? '★  ★  ★    Y O U   W I N    ★  ★  ★'
      : youCoins < aiCoins
        ? '✗  ✗  ✗    A I   W I N S    ✗  ✗  ✗'
        : '◇  ◇  ◇    T I E   G A M E    ◇  ◇  ◇';
  const youTiles =
    state.players[HUMAN].tiles.length === 0
      ? fg(DIM_TEXT) + '(none)' + RESET
      : state.players[HUMAN].tiles.map(tileCell).join(' ');
  const aiTiles =
    state.players[AI].tiles.length === 0
      ? fg(DIM_TEXT) + '(none)' + RESET
      : state.players[AI].tiles.map(tileCell).join(' ');

  out(CLEAR);
  out('\n\n');
  out(panelTop('GAME OVER') + '\n');
  out(panelLine('') + '\n');
  out(panelLine('  ' + fg(headColor) + BOLD + heading + RESET) + '\n');
  out(panelLine('') + '\n');
  out(
    panelLine(
      '  ' + fg(Cy_BR) + BOLD + 'YOU       '.padEnd(LABEL_WIDTH, ' ') + RESET +
        '  ' + fg(A_GLINT) + BOLD + youCoins + RESET + ' coins',
    ) + '\n',
  );
  out(panelLine('                ' + youTiles) + '\n');
  out(panelLine('') + '\n');
  out(
    panelLine(
      '  ' + fg(Mg_BR) + BOLD + ('AI (' + aiDiscipline.toFixed(1) + ')').padEnd(LABEL_WIDTH, ' ') + RESET +
        '  ' + fg(A_GLINT) + BOLD + aiCoins + RESET + ' coins',
    ) + '\n',
  );
  out(panelLine('                ' + aiTiles) + '\n');
  out(panelLine('') + '\n');
  out(panelBottom() + '\n');
  out('   ' + fg(DIM_TEXT) + '[any key to exit]' + RESET);
}

// ─── main loop ──────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const aiDiscipline = parseDiscipline(process.argv.slice(2)) ?? DEFAULT_DISCIPLINE;
  const ai: Difficulty = { discipline: aiDiscipline };

  setupInput();
  await boot();

  const rng: Rng = Math.random;
  let state = initialState(['YOU', 'AI']);
  const baseOpts: RenderOpts = { aiDiscipline };

  while (state.phase !== 'over') {
    let action: Action;
    if (state.current === HUMAN) {
      render(state, { ...baseOpts, footer: promptText(state) });
      out(SHOW_CURSOR);
      const choice = await promptHuman(state);
      out(HIDE_CURSOR);
      if (choice === 'QUIT') {
        teardownInput();
        return;
      }
      action = choice;
    } else {
      render(state, {
        ...baseOpts,
        footer: fg(DIM_TEXT) + 'AI thinking…' + RESET,
      });
      action = await aiTurnAction(state, ai);
    }

    const before = state;
    const after = step(state, action, rng);

    if (action.type === 'ROLL' && after.rolled.length > 0) {
      await animateRoll(before, after, baseOpts);
    }

    state = after;
    await effects(before, state, baseOpts);
  }

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
  console.error(err);
  process.exit(1);
});
