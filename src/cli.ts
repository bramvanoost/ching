// CHING solo CLI: human vs AI in one terminal. Thin loop on top of
// render.ts (pure) + term.ts (I/O) + engine + ai.

import {
  COIN,
  bankOptions,
  initialState,
  step,
  type Action,
  type BankOption,
  type Face,
  type Rng,
  type State,
} from './engine.js';
import { decide, type Difficulty } from './ai.js';
import {
  A_GLINT,
  BOLD,
  CLEAR,
  DIM_TEXT,
  P_BR,
  P_DIM,
  P_LIME,
  P_LIME2,
  P_MED,
  RED,
  RESET,
  TEXT,
  bootBanner,
  fg,
  flashFrame,
  renderFrame,
  renderGameOver,
  seatColor,
  setAsideSum,
  tileBadge,
  type ViewOpts,
} from './render.js';
import {
  delay,
  drawFrame,
  hideCursor,
  playFlash,
  playRoll,
  readKeyMatching,
  setupTerm,
  showCursor,
  teardownTerm,
  typewrite,
  waitKey,
  writeRaw,
} from './term.js';

const HUMAN = 0;
const AI_SEAT = 1;
const DEFAULT_DISCIPLINE = 0.6;
const AI_THINK_MS = 380;

function viewFor(aiDiscipline: number): Omit<ViewOpts, 'footer' | 'spinIdx' | 'spinFrame' | 'spinGlint'> {
  return {
    viewerSeat: HUMAN,
    seats: [
      { label: 'YOU', color: seatColor(HUMAN), kind: 'human', connected: true },
      {
        label: 'AI (' + aiDiscipline.toFixed(1) + ')',
        color: seatColor(AI_SEAT),
        kind: 'ai',
        connected: true,
      },
    ],
  };
}

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
  if (state.phase === 'chooseBank') {
    const opts = bankOptions(state);
    const parts: string[] = [];
    let i = 1;
    for (const o of opts) {
      const key = String(i++);
      if (o.kind === 'steal') {
        const name = state.players[o.playerIndex].id;
        parts.push(
          fg(P_LIME) + '[' + fg(A_GLINT) + BOLD + key + RESET + fg(P_LIME) +
            '] steal ' + name + "'s " + o.tile + RESET,
        );
      } else {
        parts.push(
          fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + key + RESET + fg(P_LIME) +
            '] take ' + o.tile + ' from the center' + RESET,
        );
      }
    }
    return fg(P_LIME) + '> ' + parts.join('  ') + ' ' + RESET;
  }
  const canStop = state.setAside.length > 0;
  const choices = [fg(P_LIME) + '[' + fg(P_LIME2) + BOLD + 'R' + RESET + fg(P_LIME) + ']oll' + RESET];
  if (canStop) {
    choices.push(fg(P_LIME) + '[' + fg(A_GLINT) + BOLD + 'S' + RESET + fg(P_LIME) + ']top' + RESET);
  }
  choices.push(fg(DIM_TEXT) + '[Q]uit' + RESET);
  return fg(P_LIME) + '> ' + choices.join('  ') + ' ' + RESET;
}

async function promptHuman(state: State): Promise<Action | 'QUIT'> {
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
  if (state.phase === 'chooseBank') {
    const opts = bankOptions(state);
    const k = await readKeyMatching((k) => {
      const n = Number(k);
      return Number.isInteger(n) && n >= 1 && n <= opts.length;
    });
    if (k === 'q') return 'QUIT';
    const target: BankOption = opts[Number(k) - 1];
    return { type: 'BANK', target };
  }
  const canStop = state.setAside.length > 0;
  const k = await readKeyMatching((k) => k === 'r' || (canStop && k === 's'));
  if (k === 'q') return 'QUIT';
  return k === 'r' ? { type: 'ROLL' } : { type: 'STOP' };
}

async function aiTurnAction(state: State, ai: Difficulty): Promise<Action> {
  await delay(AI_THINK_MS);
  return decide(state, ai);
}

async function boot(): Promise<void> {
  // Boot is an incremental typewriter sequence: each line builds on the
  // previous cursor position (label, then dots that ACCUMULATE horizontally,
  // then 'OK\n'). Use writeRaw, not drawFrame: drawFrame is cursor-home +
  // erase-tail and would wipe each prior line.
  writeRaw(CLEAR + fg(P_BR));
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
    writeRaw(fg(P_MED) + '> ' + RESET + fg(P_BR) + label + RESET);
    const dots = 36 - label.length;
    for (let i = 0; i < dots; i++) {
      writeRaw(fg(P_DIM) + '.' + RESET);
      await delay(ms / dots);
    }
    writeRaw(fg(A_GLINT) + BOLD + 'OK' + RESET + '\n');
    await delay(70);
  }
  writeRaw(fg(P_MED) + '> ' + fg(P_LIME2) + BOLD + 'READY.' + RESET + '\n\n');
  await delay(260);

  // From here on we paint full screens via drawFrame.
  drawFrame(CLEAR + bootBanner() +
    '\n   ' + fg(P_BR) + 'push your luck  •  collect  •  steal  •  ' +
    fg(A_GLINT) + BOLD + 'CHING!' + RESET + '\n\n' +
    fg(DIM_TEXT) + '   [any key to start]' + RESET);
  await waitKey();
}

async function effects(
  prev: State,
  next: State,
  baseView: Omit<ViewOpts, 'footer' | 'spinIdx' | 'spinFrame' | 'spinGlint'>,
): Promise<void> {
  if (next.current === prev.current && next.phase !== 'over') return;
  const actor = prev.current;
  const prevTiles = prev.players[actor].tiles.length;
  const nextTiles = next.players[actor].tiles.length;
  const prevCenter = prev.centerTiles.length;
  const nextCenter = next.centerTiles.length;
  const sum = setAsideSum(prev);

  if (nextTiles > prevTiles) {
    const tile = next.players[actor].tiles[next.players[actor].tiles.length - 1];
    drawFrame(renderFrame(next, baseView));
    if (nextCenter < prevCenter) {
      await playFlash(flashFrame('◆  K A · C H I N G !  ◆   banked ' + tileBadge(tile), A_GLINT), true);
    } else {
      await playFlash(flashFrame('▶  S T E A L !  ◀   took ' + tileBadge(tile), seatColor(AI_SEAT)), true);
    }
  } else if (
    nextTiles < prevTiles ||
    nextCenter < prevCenter ||
    (prev.setAside.length > 0 && nextCenter >= prevCenter)
  ) {
    drawFrame(renderFrame(next, baseView));
    await playFlash(flashFrame('✗  B U S T !  ✗   sum was ' + sum, RED), false);
  }
}

async function animateRollFor(
  before: State,
  after: State,
  baseView: Omit<ViewOpts, 'footer' | 'spinIdx' | 'spinFrame' | 'spinGlint'>,
): Promise<void> {
  if (after.rolled.length === 0) return;
  const partial: State = { ...before, rolled: [], phase: 'pick' };
  const footer = fg(DIM_TEXT) + 'rolling…' + RESET;

  await playRoll(after.rolled, ({ rolledSoFar, spinIdx, spinFrame, spinGlint }) => {
    const visible = after.rolled.slice(0, rolledSoFar);
    const snap: State = { ...partial, rolled: visible };
    return renderFrame(snap, { ...baseView, footer, spinIdx, spinFrame, spinGlint });
  });
}

// Pure solo-vs-AI game loop. Assumes term is already set up by the caller
// (the launcher or this file's own main). Identical to the pre-launcher
// experience under `npm run play` so a CLAUDE.md "Single player must remain
// bit-for-bit current" guarantee holds.
export async function runSolo(opts: { discipline?: number } = {}): Promise<void> {
  const aiDiscipline = opts.discipline ?? DEFAULT_DISCIPLINE;
  const ai: Difficulty = { discipline: aiDiscipline };

  await boot();

  const rng: Rng = Math.random;
  let state = initialState(['YOU', 'AI']);
  const baseView = viewFor(aiDiscipline);

  while (state.phase !== 'over') {
    let action: Action;
    if (state.current === HUMAN) {
      drawFrame(renderFrame(state, { ...baseView, footer: promptText(state) }));
      showCursor();
      const choice = await promptHuman(state);
      hideCursor();
      if (choice === 'QUIT') return;
      action = choice;
    } else {
      drawFrame(
        renderFrame(state, {
          ...baseView,
          footer: fg(DIM_TEXT) + 'AI thinking…' + RESET,
        }),
      );
      action = await aiTurnAction(state, ai);
    }

    const before = state;
    const after = step(state, action, rng);

    if (action.type === 'ROLL' && after.rolled.length > 0) {
      await animateRollFor(before, after, baseView);
    }

    state = after;
    await effects(before, state, baseView);
  }

  drawFrame(renderGameOver(state, baseView));
  await waitKey();
}

async function main(): Promise<void> {
  const aiDiscipline = parseDiscipline(process.argv.slice(2)) ?? DEFAULT_DISCIPLINE;
  setupTerm();
  try {
    await runSolo({ discipline: aiDiscipline });
  } finally {
    teardownTerm();
  }
}

export { DEFAULT_DISCIPLINE, parseDiscipline };

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

// Only run main() when cli.ts is the script entry. Without this guard,
// importing runSolo from launcher.ts (or tests) would fire main() at import
// time and enter alt-screen mode, breaking everything.
const isEntry = process.argv[1] && import.meta.url === 'file://' + process.argv[1];
if (isEntry) {
  main().catch((err) => {
    teardownTerm();
    console.error(err);
    process.exit(1);
  });
}
