// CHING renderer. Pure: state + ViewOpts -> ANSI strings.
// No process.stdout, no setTimeout, no env reads. ANSI escapes are emitted
// unconditionally so snapshot tests are stable across TERM/FORCE_COLOR.

import {
  COIN,
  tileCoins,
  type Face,
  type State,
} from './engine.js';

// ─── 256-color CRT palette ──────────────────────────────────────────────────
export const ESC = '\x1b[';
export const fg = (n: number): string => ESC + '38;5;' + n + 'm';
export const RESET = ESC + '0m';
export const BOLD = ESC + '1m';
export const DIM = ESC + '2m';
export const INVERT = ESC + '7m';
export const CLEAR = ESC + 'H' + ESC + '2J';
export const HIDE_CURSOR = ESC + '?25l';
export const SHOW_CURSOR = ESC + '?25h';
export const ENTER_ALT = ESC + '?1049h';
export const EXIT_ALT = ESC + '?1049l';
export const BELL = '\x07';

// Phosphor green (dim → neon → lime)
export const P_DARK = 22;
export const P_DIM = 28;
export const P_MED = 34;
export const P_BR = 40;
export const P_NEON = 46;
export const P_LIME = 82;
export const P_LIME2 = 118;
export const P_LIME3 = 154;
export const PHOSPHOR_GRADIENT = [
  P_DARK, P_DIM, P_MED, P_BR, P_NEON, P_LIME, P_LIME2, P_LIME3,
  P_LIME2, P_LIME, P_NEON, P_BR, P_MED, P_DIM, P_DARK,
];

// Amber CRT
export const A_DIM = 130;
export const A_MED = 178;
export const A_BR = 214;
export const A_GLINT = 220;

// Cool accents
export const Cy_BR = 51;
export const Mg_BR = 207;

// Tile tiers
export const TIER1 = 246;
export const TIER2 = 38;
export const TIER3 = 135;
export const TIER4 = 214;

// Surfaces
export const TEXT = 252;
export const DIM_TEXT = 244;
export const SHADOW = 235;
export const RED = 196;

// Seat colors. Indexed by seat number; bounded by modulo so a future cap
// increase cannot index out of range.
export const SEAT_PALETTE: readonly number[] = [Cy_BR, Mg_BR, A_GLINT, P_LIME2];
export const seatColor = (seat: number): number =>
  SEAT_PALETTE[((seat % SEAT_PALETTE.length) + SEAT_PALETTE.length) % SEAT_PALETTE.length];

// ─── visual constants ───────────────────────────────────────────────────────
export const INNER = 66;
const SHADOW_CHAR = '▒';
const LABEL_WIDTH = 10;

const COIN_SPIN: readonly string[] = ['◐', '◓', '◑', '◒'];
const COIN_STATIC = '◆';

export const GEM = '◆';
export const GEM_EMPTY = '◇';
const GEM_GRADIENT: readonly number[] = [220, 226, 230];

// ─── helpers ────────────────────────────────────────────────────────────────
export function visibleLen(s: string): number {
  return s.replace(/\x1b\[[\d;?]*[A-Za-z]/g, '').length;
}

function gems(count: number): string {
  let s = '';
  for (let i = 0; i < count; i++) {
    s += fg(GEM_GRADIENT[i % GEM_GRADIENT.length]) + BOLD + GEM + RESET;
  }
  return s;
}

function plainGems(count: number): string {
  return GEM.repeat(count);
}

// ─── panel primitives (bevel + drop shadow) ─────────────────────────────────
export function panelTop(label?: string, inner = INNER): string {
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

export function panelLine(content: string, inner = INNER): string {
  const vis = visibleLen(content);
  const pad = ' '.repeat(Math.max(0, inner - vis));
  return (
    fg(P_BR) + '║' + RESET + content + pad +
    fg(P_BR) + '║' + RESET +
    fg(SHADOW) + SHADOW_CHAR + RESET
  );
}

export function panelBottom(inner = INNER): string {
  const bot =
    fg(P_DIM) + '╚' + '═'.repeat(inner) + '╝' + RESET +
    fg(SHADOW) + SHADOW_CHAR + RESET;
  const shadowRow = ' ' + fg(SHADOW) + SHADOW_CHAR.repeat(inner + 2) + RESET;
  return bot + '\n' + shadowRow;
}

// ─── cell renderers ─────────────────────────────────────────────────────────
function tileCell(t: number): string {
  const c = tileCoins(t);
  const color = c === 1 ? TIER1 : c === 2 ? TIER2 : c === 3 ? TIER3 : TIER4;
  return fg(color) + '[' + t + ' ' + RESET + gems(c) + fg(color) + ']' + RESET;
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
  return (
    fg(A_MED) + '[' + fg(A_GLINT) + BOLD + COIN_STATIC + RESET +
    fg(A_MED) + ']' + RESET
  );
}

function dieCell(f: Face, spinFrame?: number, glint?: boolean): string {
  if (f === COIN) return coinCell(spinFrame, glint);
  return fg(DIM_TEXT) + '[' + fg(TEXT) + String(f) + fg(DIM_TEXT) + ']' + RESET;
}

export function setAsideSum(state: State): number {
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

function rolledLine(state: State, opts: ViewOpts): string {
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

// ─── ViewOpts ───────────────────────────────────────────────────────────────
export type SeatView = {
  label: string;
  color: number;
  kind: 'human' | 'ai' | 'ai-takeover';
  connected: boolean;
};

export type ViewOpts = {
  viewerSeat: number | null;
  seats: readonly SeatView[];
  footer?: string;
  spinIdx?: number;
  spinFrame?: number;
  spinGlint?: boolean;
};

function seatLineContent(seat: SeatView, p: State['players'][number]): string {
  const padded = seat.label.padEnd(LABEL_WIDTH, ' ');
  const coins = p.tiles.reduce((s, t) => s + tileCoins(t), 0);
  const tiles =
    p.tiles.length === 0
      ? fg(DIM_TEXT) + GEM_EMPTY + ' empty vault' + RESET
      : p.tiles.map(tileCell).join(' ');
  const labelStyle = seat.connected ? BOLD : DIM;
  return (
    fg(seat.color) + labelStyle + padded + RESET + '  ' + tiles + '   ' +
    fg(DIM_TEXT) + 'coins:' + RESET + ' ' +
    fg(A_GLINT) + BOLD + coins + RESET
  );
}

// ─── full-frame render ──────────────────────────────────────────────────────
export function renderFrame(state: State, opts: ViewOpts): string {
  const lines: string[] = [];
  lines.push(CLEAR);

  // Header.
  const titleLeft = fg(P_LIME2) + BOLD + 'CHING' + RESET + fg(P_MED) + ' v0.1' + RESET;
  const titleRight = fg(A_MED) + '8-BIT TERMINAL EDITION' + RESET;
  const gap = Math.max(1, INNER - 4 - visibleLen(titleLeft) - visibleLen(titleRight));
  lines.push(panelTop() + '\n');
  lines.push(panelLine('  ' + titleLeft + ' '.repeat(gap) + titleRight + '  ') + '\n');
  lines.push(panelBottom() + '\n');

  // Center tiles.
  lines.push(
    panelTop(
      'CENTER TILES  ' +
        fg(DIM_TEXT) + '(' + RESET +
        fg(GEM_GRADIENT[1]) + BOLD + GEM + RESET +
        fg(DIM_TEXT) + ' = coins per tile)' + RESET +
        fg(P_LIME2) + BOLD,
    ) + '\n',
  );
  if (state.centerTiles.length === 0) {
    lines.push(panelLine('  ' + fg(DIM_TEXT) + '(empty)' + RESET) + '\n');
  } else {
    const cells = state.centerTiles.map(tileCell);
    for (let i = 0; i < cells.length; i += 6) {
      lines.push(panelLine('  ' + cells.slice(i, i + 6).join(' ')) + '\n');
    }
  }
  lines.push(panelBottom() + '\n');

  // Vaults — one row per seat in seat order.
  lines.push(panelTop('VAULTS') + '\n');
  for (let i = 0; i < state.players.length; i++) {
    const seat = opts.seats[i];
    lines.push(panelLine('  ' + seatLineContent(seat, state.players[i])) + '\n');
  }
  lines.push(panelBottom() + '\n');

  // Current turn.
  const turn = opts.seats[state.current];
  lines.push(
    panelTop(
      'TURN: ' + fg(turn.color) + BOLD + turn.label + RESET + fg(P_LIME2) + BOLD,
    ) + '\n',
  );

  lines.push(
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
  lines.push(
    panelLine(
      '  ' + fg(DIM_TEXT) + 'set aside ' + RESET + setAsideStr + '   ' +
        fg(DIM_TEXT) + 'sum:' + RESET + ' ' +
        fg(sumColor) + BOLD + sum + RESET + coinFlag,
    ) + '\n',
  );
  lines.push(
    panelLine(
      '  ' + fg(DIM_TEXT) + 'picked    ' + RESET + pickedSummary(state) + '   ' +
        fg(DIM_TEXT) + 'dice in hand:' + RESET + ' ' + state.diceInHand,
    ) + '\n',
  );
  lines.push(panelBottom() + '\n');

  if (opts.footer) {
    lines.push('   ' + opts.footer);
  }

  return lines.join('');
}

// ─── game over ──────────────────────────────────────────────────────────────
export function renderGameOver(state: State, opts: ViewOpts): string {
  const lines: string[] = [];
  const scores = state.players.map((p) => p.tiles.reduce((s, t) => s + tileCoins(t), 0));
  const maxScore = Math.max(...scores);
  const winners = scores
    .map((s, i) => (s === maxScore ? i : -1))
    .filter((i) => i >= 0);
  const viewer = opts.viewerSeat;

  let heading: string;
  let headColor: number;
  if (winners.length > 1) {
    heading = '◇  ◇  ◇    T I E   G A M E    ◇  ◇  ◇';
    headColor = Cy_BR;
  } else if (viewer !== null && winners[0] === viewer) {
    heading = '◆  ◆  ◆    Y O U   W I N    ◆  ◆  ◆';
    headColor = A_GLINT;
  } else {
    const w = opts.seats[winners[0]];
    heading = '✗  ✗  ✗    ' + w.label + '   W I N S    ✗  ✗  ✗';
    headColor = RED;
  }

  lines.push(CLEAR);
  lines.push('\n\n');
  lines.push(panelTop('GAME OVER') + '\n');
  lines.push(panelLine('') + '\n');
  lines.push(panelLine('  ' + fg(headColor) + BOLD + heading + RESET) + '\n');
  lines.push(panelLine('') + '\n');

  for (let i = 0; i < state.players.length; i++) {
    const seat = opts.seats[i];
    const tiles = state.players[i].tiles;
    const tilesStr =
      tiles.length === 0
        ? fg(DIM_TEXT) + GEM_EMPTY + ' empty vault' + RESET
        : tiles.map(tileCell).join(' ');
    lines.push(
      panelLine(
        '  ' + fg(seat.color) + BOLD + seat.label.padEnd(LABEL_WIDTH, ' ') + RESET +
          '  ' + fg(A_GLINT) + BOLD + scores[i] + RESET + ' coins',
      ) + '\n',
    );
    lines.push(panelLine('                ' + tilesStr) + '\n');
    if (i < state.players.length - 1) lines.push(panelLine('') + '\n');
  }
  lines.push(panelLine('') + '\n');
  lines.push(panelBottom() + '\n');
  lines.push('   ' + fg(DIM_TEXT) + '[any key to exit]' + RESET);

  return lines.join('');
}

// ─── boot banner (gradient ASCII) ───────────────────────────────────────────
const BANNER = [
  '    ██████  ██   ██  ██  ███   ██   ██████  ',
  '   ██       ██   ██  ██  ████  ██  ██       ',
  '   ██       ███████  ██  ██ ██ ██  ██   ███ ',
  '   ██       ██   ██  ██  ██  ████  ██    ██ ',
  '    ██████  ██   ██  ██  ██   ██    ██████  ',
];

export function bootBanner(): string {
  const width = Math.max(...BANNER.map((l) => l.length));
  let buf = '';
  for (const line of BANNER) {
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

// ─── flash banner frames (overlays for the footer row, overwritten with \r)
export type FlashFrame = { on: string; blank: string; settle: string };

export function flashFrame(text: string, color: number): FlashFrame {
  const on = '   ' + fg(color) + BOLD + INVERT + ' ' + text + ' ' + RESET;
  const blank = '   ' + ' '.repeat(visibleLen(text) + 2);
  const settle = '   ' + fg(color) + BOLD + text + RESET;
  return { on, blank, settle };
}

export function tileBadge(tile: number): string {
  return '[' + tile + ' ' + plainGems(tileCoins(tile)) + ']';
}
