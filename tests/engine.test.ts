import { describe, it, expect } from 'vitest';
import {
  bankOptions,
  initialState,
  step,
  type Rng,
  type Face,
  type State,
} from '../src/engine.js';

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

  it('auto-resolves the steal when no center tile <= sum is available', () => {
    // Roll all coins; pick them; STOP with sum=30 matching rival B's top tile.
    // Strip every center tile <= 30 so steal is the only legal option and
    // the bank commits without entering chooseBank.
    const rng = rngForFaces([6, 6, 6, 6, 6, 6, 1, 1]);
    let s = initialState(['A', 'B']);
    s = {
      ...s,
      current: 0,
      players: [
        { id: 'A', tiles: [] },
        { id: 'B', tiles: [30] },
      ],
      centerTiles: s.centerTiles.filter((t) => t > 30),
    };
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 6 }, rng);
    expect(s.setAside.length).toBe(6);
    expect(s.diceInHand).toBe(2);
    expect(s.phase).toBe('roll');
    s = step(s, { type: 'STOP' }, rng);
    expect(s.phase).toBe('roll'); // turn advanced, not parked in chooseBank
    expect(s.players[0].tiles).toEqual([30]); // A stole 30
    expect(s.players[1].tiles).toEqual([]); // B lost 30
  });

  it('enters chooseBank when both steal and center take are possible', () => {
    // sum 30, rival has [30], center still has every tile incl. 29 (and 30
    // is absent because the rival holds it). Player should be offered a
    // choice between stealing 30 and taking 29 from the supply.
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
    s = step(s, { type: 'STOP' }, rng);

    expect(s.phase).toBe('chooseBank');
    expect(s.current).toBe(0); // turn hasn't advanced yet
    const opts = bankOptions(s);
    expect(opts).toEqual([
      { kind: 'steal', playerIndex: 1, tile: 30 },
      { kind: 'center', tile: 29 },
    ]);

    // Commit the steal: B loses 30, A gains 30, supply untouched.
    const afterSteal = step(s, { type: 'BANK', target: { kind: 'steal', playerIndex: 1, tile: 30 } }, rng);
    expect(afterSteal.players[0].tiles).toEqual([30]);
    expect(afterSteal.players[1].tiles).toEqual([]);
    expect(afterSteal.centerTiles).toContain(29);
    expect(afterSteal.current).toBe(1);
  });

  it('lets the player take the last center tile instead of forced-stealing', () => {
    // Bram's scenario: supply has only 25, rival has top tile 26, player
    // rolls 26. Old engine forced the steal; new engine offers both. If
    // the player takes 25 they empty the supply and the game ends.
    const rng: Rng = () => 0;
    let s = initialState(['A', 'B']);
    s = {
      ...s,
      current: 0,
      phase: 'roll',
      players: [
        { id: 'A', tiles: [] },
        { id: 'B', tiles: [26] },
      ],
      centerTiles: [25],
      diceInHand: 0,
      setAside: [6, 6, 6, 6, 6, 1] as Face[], // sum 26 (coin=5 each)
    };
    s = step(s, { type: 'STOP' }, rng);
    expect(s.phase).toBe('chooseBank');
    const opts = bankOptions(s);
    expect(opts).toEqual([
      { kind: 'steal', playerIndex: 1, tile: 26 },
      { kind: 'center', tile: 25 },
    ]);

    const afterCenter = step(s, { type: 'BANK', target: { kind: 'center', tile: 25 } }, rng);
    expect(afterCenter.phase).toBe('over'); // supply empty -> game ends
    expect(afterCenter.players[0].tiles).toEqual([25]);
    expect(afterCenter.players[1].tiles).toEqual([26]); // rival keeps their shell
    expect(afterCenter.centerTiles).toEqual([]);
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
