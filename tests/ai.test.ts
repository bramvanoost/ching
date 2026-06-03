import { describe, it, expect } from 'vitest';
import { initialState, step, type Rng, type Face } from '../src/engine.js';
import { decide } from '../src/ai.js';

function rngForFaces(faces: Face[]): Rng {
  let i = 0;
  return () => {
    const f = faces[i % faces.length];
    i++;
    return (f - 1) / 6 + 0.0001;
  };
}

describe('CHING ai', () => {
  it('rolls at the start of a turn', () => {
    const s = initialState(['A', 'B']);
    const a = decide(s, { discipline: 0.5 });
    expect(a).toEqual({ type: 'ROLL' });
  });

  it('picks the coin first when no coin is set aside yet', () => {
    // Roll contains a coin (6) plus larger groups of other faces.
    // Without the coin, no bank is possible, so AI must grab the coin.
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5]);
    let s = initialState(['A', 'B']);
    s = step(s, { type: 'ROLL' }, rng);
    const a = decide(s, { discipline: 0.5 });
    expect(a).toEqual({ type: 'PICK', face: 6 });
  });
});
