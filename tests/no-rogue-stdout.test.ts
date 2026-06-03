// Frame-write guard. Asserts no source file outside the controlled set ever
// writes to process.stdout or calls console.log. Frame writes must flow
// through term.drawFrame so the cursor-home + erase-tail invariant holds and
// the screen can never stack / append. console.error is allowed everywhere
// (it's only used on error-exit paths, after teardownTerm restores the TTY).
//
// Allow-list rationale:
//   - src/term.ts : owns the single out() that drives drawFrame/drawFooter,
//                   plus playFlash and the boot writeRaw. All controlled.
//   - src/net/log.ts : daemon-process structured logger; writes to the
//                   daemon's stdout, which is a different process from the
//                   client TTY.

import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(process.cwd(), 'src');
const ALLOW = new Set([
  join(ROOT, 'term.ts'),
  join(ROOT, 'net', 'log.ts'),
]);

function walk(dir: string, acc: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) walk(p, acc);
    else if (name.endsWith('.ts')) acc.push(p);
  }
  return acc;
}

const FORBIDDEN = [
  // Raw stdout write outside the allow-list bypasses drawFrame.
  /process\.stdout\.write\s*\(/,
  // console.log is only used (today) for frames; if you genuinely need it,
  // route through the daemon logger or use console.error for crash paths.
  /\bconsole\.log\s*\(/,
];

describe('no rogue stdout writes', () => {
  it('only src/term.ts and src/net/log.ts may touch process.stdout or console.log', () => {
    const files = walk(ROOT);
    const violations: string[] = [];
    for (const file of files) {
      if (ALLOW.has(file)) continue;
      const src = readFileSync(file, 'utf8');
      for (const pat of FORBIDDEN) {
        const m = pat.exec(src);
        if (m) {
          const before = src.slice(0, m.index);
          const line = before.split('\n').length;
          violations.push(file + ':' + line + ': ' + pat.source);
        }
      }
    }
    expect(violations).toEqual([]);
  });
});
