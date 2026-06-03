import { describe, it, expect } from 'vitest';
import { initialState, step, type Rng, type Face, type State } from '../src/engine.js';

// rngForFaces: returns a deterministic Rng that produces dice with the given faces in order.
// engine's rollDie maps rng() in [(f-1)/6, f/6) to face f.
function rngForFaces(faces: Face[]): Rng {
  let i = 0;
  return () => {
    const f = faces[i % faces.length];
    i++;
    return (f - 1) / 6 + 0.0001;
  };
}

describe('CHING engine', () => {
  it('takes the highest center tile <= sum on a valid bank', () => {
    // First roll: pick coin (worth 5). Second roll (7 dice all 5s): pick fives.
    // Sum = 5 + 7*5 = 40. Largest tile <= 40 is 36.
    const rng = rngForFaces([
      6, 5, 5, 5, 5, 5, 5, 5, // initial 8-die roll
      5, 5, 5, 5, 5, 5, 5,    // re-roll of the 7 remaining
    ]);
    let s = initialState(['A', 'B']);
    s = step(s, { type: 'ROLL' }, rng);
    expect(s.phase).toBe('pick');
    expect(s.rolled).toEqual([6, 5, 5, 5, 5, 5, 5, 5]);
    s = step(s, { type: 'PICK', face: 6 }, rng); // coin into setAside
    expect(s.setAside).toEqual([6]);
    expect(s.diceInHand).toBe(7);
    expect(s.phase).toBe('roll');
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 5 }, rng); // exhausts dice -> auto-bank
    expect(s.players[0].tiles).toEqual([36]);
    expect(s.centerTiles).not.toContain(36);
    expect(s.current).toBe(1); // turn advanced
  });

  it('returns the top tile and burns the highest center tile on a bust', () => {
    // All 1s: pick 1s, no coin -> auto-stop on empty hand -> bust.
    const rng = rngForFaces([1, 1, 1, 1, 1, 1, 1, 1]);
    let s = initialState(['A', 'B']);
    // Seed A with a banked tile and remove it from the center.
    s = {
      ...s,
      players: [
        { id: 'A', tiles: [25] },
        { id: 'B', tiles: [] },
      ],
      centerTiles: s.centerTiles.filter((t) => t !== 25),
    };
    const highestBefore = Math.max(...s.centerTiles);
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 1 }, rng); // diceInHand -> 0 triggers auto-stop, no coin -> bust
    expect(s.players[0].tiles).toEqual([]); // A lost its top tile
    expect(s.centerTiles).toContain(25); // returned tile is back in the center
    expect(s.centerTiles).not.toContain(highestBefore); // highest tile was burned
    expect(s.current).toBe(1);
  });

  it('only burns a center tile on bust if the center has tiles after the return', () => {
    // Edge: busting player has no tiles to return AND center is empty.
    const rng = rngForFaces([1, 1, 1, 1, 1, 1, 1, 1]);
    let s = initialState(['A', 'B']);
    s = { ...s, centerTiles: [] };
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 1 }, rng);
    // No tile to return, no tile to burn, game has no banks left -> over.
    expect(s.centerTiles).toEqual([]);
    expect(s.phase).toBe('over');
  });

  it('steals a rival top tile on exact-match bank', () => {
    // Roll all coins; pick them; STOP with sum=30 matching rival B's top tile.
    const rng = rngForFaces([6, 6, 6, 6, 6, 6, 1, 1]);
    let s = initialState(['A', 'B']);
    s = {
      ...s,
      current: 0,
      players: [
        { id: 'A', tiles: [] },
        { id: 'B', tiles: [30] },
      ],
      centerTiles: s.centerTiles.filter((t) => t !== 30),
    };
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 6 }, rng);
    expect(s.setAside.length).toBe(6);
    expect(s.diceInHand).toBe(2);
    expect(s.phase).toBe('roll');
    s = step(s, { type: 'STOP' }, rng);
    expect(s.players[0].tiles).toEqual([30]); // A stole 30
    expect(s.players[1].tiles).toEqual([]); // B lost 30
  });

  it('ends the game when the last center tile is banked', () => {
    const rng = rngForFaces([6, 6, 6, 6, 6, 6, 1, 1]);
    let s = initialState(['A', 'B']);
    s = { ...s, centerTiles: [30] };
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 6 }, rng);
    s = step(s, { type: 'STOP' }, rng);
    expect(s.phase).toBe('over');
    expect(s.players[0].tiles).toEqual([30]);
    expect(s.centerTiles).toEqual([]);
  });
});
