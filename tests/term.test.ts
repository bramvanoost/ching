// Tests the cursor-home + erase-tail invariant of drawFrame, and the
// in-place footer repaint via drawFooter. We monkey-patch process.stdout
// .write so we can inspect every byte the term layer emits without actually
// hitting a TTY.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { drawFooter, drawFrame, teardownTerm, writeRaw } from '../src/term.js';

let written = '';
let origWrite: typeof process.stdout.write;

beforeEach(() => {
  written = '';
  origWrite = process.stdout.write.bind(process.stdout);
  // Capture instead of writing.
  (process.stdout.write as unknown) = (chunk: string | Uint8Array): boolean => {
    written += typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
    return true;
  };
});

afterEach(() => {
  (process.stdout.write as unknown) = origWrite;
  // Reset internal frame-row tracking between tests.
  teardownTerm();
});

describe('drawFrame invariants', () => {
  it('prefixes cursor-home and suffixes erase-tail', () => {
    drawFrame('hello\nworld');
    expect(written.startsWith('\x1b[H')).toBe(true);
    expect(written.endsWith('\x1b[J')).toBe(true);
    expect(written.includes('hello\nworld')).toBe(true);
  });

  it('two successive drawFrames both repaint from home (no append)', () => {
    drawFrame('A\nB\nC');
    drawFrame('X\nY');
    // Each frame must have its own \x1b[H prefix.
    const homes = written.match(/\x1b\[H/g) ?? [];
    expect(homes.length).toBe(2);
  });

  it('records the footer row for a multi-line frame', () => {
    drawFrame('row1\nrow2\nrow3\nfooter');
    written = '';
    const ok = drawFooter('FOOT');
    expect(ok).toBe(true);
    // Footer is on row 4 (3 newlines + 1).
    expect(written).toBe('\x1b[4;1H\x1b[2KFOOT');
  });
});

describe('drawFooter', () => {
  it('returns false before any frame has been drawn', () => {
    // teardownTerm in beforeEach reset the row tracking.
    expect(drawFooter('x')).toBe(false);
  });

  it('positions to the recorded footer row and erases the line first', () => {
    drawFrame('a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk');
    written = '';
    drawFooter('NEW FOOTER');
    // 10 newlines, footer row = 11.
    expect(written).toBe('\x1b[11;1H\x1b[2KNEW FOOTER');
  });

  it('successive ticks of the same countdown repaint the same row', () => {
    drawFrame('header\n----\nfooter');
    written = '';
    drawFooter('15s');
    drawFooter('10s');
    drawFooter('5s');
    // Each call writes the same row position (3) + erase + content.
    expect(written).toBe(
      '\x1b[3;1H\x1b[2K15s' +
      '\x1b[3;1H\x1b[2K10s' +
      '\x1b[3;1H\x1b[2K5s',
    );
  });
});

describe('writeRaw', () => {
  it('does not add cursor-home or erase-tail', () => {
    writeRaw('hello');
    expect(written).toBe('hello');
  });
});
