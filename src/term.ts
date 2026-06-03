// Terminal I/O. Owns alt-screen, raw mode, input queue, frame writer, and
// animation orchestration. Idempotent teardown so signal handlers and BYE
// paths can call it safely from anywhere.

import {
  BELL,
  ENTER_ALT,
  EXIT_ALT,
  HIDE_CURSOR,
  SHOW_CURSOR,
  RESET,
  type FlashFrame,
} from './render.js';

const ROLL_REVEAL_MS = 70;
const COIN_SPIN_MS = 55;
const COIN_SPIN_FRAMES = 4;
const COIN_GLINT_MS = 100;
const FLASH_MS = 110;

let active = false;
let inputBuf = '';
const inputWaiters: Array<(c: string) => void> = [];

function out(s: string): void {
  process.stdout.write(s);
}

export function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function flushInput(): void {
  while (inputWaiters.length > 0 && inputBuf.length > 0) {
    const cb = inputWaiters.shift()!;
    const ch = inputBuf[0];
    inputBuf = inputBuf.slice(1);
    cb(ch);
  }
}

function onData(chunk: string): void {
  inputBuf += chunk;
  flushInput();
}

function onEnd(): void {
  inputBuf += 'q';
  flushInput();
}

export function setupTerm(): void {
  if (active) return;
  active = true;
  if (process.stdin.isTTY) process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', onData);
  process.stdin.on('end', onEnd);
  out(ENTER_ALT + HIDE_CURSOR);
}

export function teardownTerm(): void {
  if (!active) return;
  active = false;
  process.stdin.off('data', onData);
  process.stdin.off('end', onEnd);
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  process.stdin.pause();
  out(SHOW_CURSOR + RESET + EXIT_ALT);
}

export function waitKey(): Promise<string> {
  return new Promise((resolve) => {
    inputWaiters.push(resolve);
    flushInput();
  });
}

export async function readKeyMatching(
  predicate: (k: string) => boolean,
): Promise<string> {
  for (;;) {
    const raw = await waitKey();
    const k = raw.toLowerCase();
    if (k === '' || k === 'q') return 'q';
    if (predicate(k)) return k;
  }
}

export function drawFrame(s: string): void {
  out(s);
}

export function showCursor(): void {
  out(SHOW_CURSOR);
}

export function hideCursor(): void {
  out(HIDE_CURSOR);
}

export function bell(): void {
  out(BELL);
}

export async function typewrite(text: string, msPerChar = 8): Promise<void> {
  for (const ch of text) {
    out(ch);
    if (msPerChar > 0) await delay(msPerChar);
  }
}

// Flash the footer in place by overwriting via \r. Frames come from
// render.flashFrame so the visuals stay in the pure renderer.
export async function playFlash(frame: FlashFrame, beep: boolean): Promise<void> {
  if (beep) bell();
  for (let i = 0; i < 3; i++) {
    out('\r' + frame.on);
    await delay(FLASH_MS);
    out('\r' + frame.blank);
    await delay(FLASH_MS);
  }
  out('\r' + frame.settle);
  await delay(FLASH_MS * 2);
}

// Drive a roll-reveal animation. The caller supplies a `renderFn` that takes
// per-frame opts (spinIdx/spinFrame/spinGlint, footer) and returns the full
// frame string. Keeps render.ts free of process.stdout/setTimeout.
export type RollFrameOpts = {
  rolledSoFar: number; // how many dice are visible
  spinIdx?: number;
  spinFrame?: number;
  spinGlint?: boolean;
};
export type RollRenderer = (o: RollFrameOpts) => string;

export const COIN = 6;

export async function playRoll(
  rolled: readonly number[],
  render: RollRenderer,
): Promise<void> {
  if (rolled.length === 0) return;

  drawFrame(render({ rolledSoFar: 0 }));
  await delay(ROLL_REVEAL_MS);

  for (let i = 0; i < rolled.length; i++) {
    const newDie = rolled[i];
    if (newDie === COIN) {
      for (let frame = 0; frame < COIN_SPIN_FRAMES; frame++) {
        drawFrame(
          render({ rolledSoFar: i + 1, spinIdx: i, spinFrame: frame }),
        );
        await delay(COIN_SPIN_MS);
      }
      drawFrame(render({ rolledSoFar: i + 1, spinIdx: i, spinGlint: true }));
      await delay(COIN_GLINT_MS);
    } else {
      drawFrame(render({ rolledSoFar: i + 1 }));
      await delay(ROLL_REVEAL_MS);
    }
  }
}
