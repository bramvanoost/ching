// Snapshot tests for the pure renderer. ANSI escapes are emitted
// unconditionally so these snapshots are stable across TERM/FORCE_COLOR.

import { describe, expect, it } from 'vitest';
import { initialState, step, type Rng, type Face, type State } from '../src/engine.js';
import {
  renderFrame,
  renderGameOver,
  seatColor,
  type ViewOpts,
} from '../src/render.js';

function rngForFaces(faces: Face[]): Rng {
  let i = 0;
  return () => {
    const f = faces[i % faces.length];
    i++;
    return (f - 1) / 6 + 0.0001;
  };
}

function soloView(): ViewOpts {
  return {
    viewerSeat: 0,
    seats: [
      { label: 'YOU', color: seatColor(0), kind: 'human', connected: true },
      { label: 'AI (0.6)', color: seatColor(1), kind: 'ai', connected: true },
    ],
  };
}

function fourSeatView(viewer: number): ViewOpts {
  return {
    viewerSeat: viewer,
    seats: [
      { label: viewer === 0 ? 'YOU' : 'alice', color: seatColor(0), kind: 'human', connected: true },
      { label: viewer === 1 ? 'YOU' : 'bob', color: seatColor(1), kind: 'human', connected: true },
      { label: viewer === 2 ? 'YOU' : 'carol', color: seatColor(2), kind: 'human', connected: false },
      { label: viewer === 3 ? 'YOU' : 'AI (0.6)', color: seatColor(3), kind: 'ai', connected: true },
    ],
  };
}

describe('renderFrame', () => {
  it('renders the initial state for solo view', () => {
    const s = initialState(['YOU', 'AI']);
    expect(renderFrame(s, soloView())).toMatchSnapshot();
  });

  it('renders mid-roll (set-aside coin, dice remaining) for solo view', () => {
    const rng = rngForFaces([6, 5, 5, 5, 5, 5, 5, 5, 4, 3, 2, 1, 6, 5, 5]);
    let s = initialState(['YOU', 'AI']);
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 6 }, rng);
    s = step(s, { type: 'ROLL' }, rng);
    expect(renderFrame(s, soloView())).toMatchSnapshot();
  });

  it('renders pre-bank state with a coin set aside', () => {
    const s: State = {
      players: [{ id: 'YOU', tiles: [] }, { id: 'AI', tiles: [] }],
      current: 0,
      centerTiles: Array.from({ length: 16 }, (_, i) => 21 + i),
      diceInHand: 3,
      rolled: [],
      setAside: [6, 5, 5, 5, 5],
      pickedFaces: [6, 5],
      phase: 'roll',
    };
    expect(renderFrame(s, { ...soloView(), footer: '> [R]oll [S]top [Q]uit' })).toMatchSnapshot();
  });

  it('renders pre-bank state with NO coin (red sum, bust risk)', () => {
    const s: State = {
      players: [{ id: 'YOU', tiles: [] }, { id: 'AI', tiles: [] }],
      current: 0,
      centerTiles: Array.from({ length: 16 }, (_, i) => 21 + i),
      diceInHand: 5,
      rolled: [],
      setAside: [4, 4, 4],
      pickedFaces: [4],
      phase: 'roll',
    };
    expect(renderFrame(s, soloView())).toMatchSnapshot();
  });

  it('renders a 4-seat game from seat 2 perspective (carol disconnected)', () => {
    const s: State = {
      players: [
        { id: 'alice', tiles: [22] },
        { id: 'bob', tiles: [25, 28] },
        { id: 'carol', tiles: [] },
        { id: 'AI', tiles: [31] },
      ],
      current: 2,
      centerTiles: [23, 24, 26, 27, 29, 30, 32, 33, 34, 35, 36],
      diceInHand: 8,
      rolled: [],
      setAside: [],
      pickedFaces: [],
      phase: 'roll',
    };
    expect(renderFrame(s, fourSeatView(2))).toMatchSnapshot();
  });
});

describe('renderGameOver', () => {
  it('renders YOU WIN when viewer holds the top score', () => {
    const s: State = {
      players: [
        { id: 'YOU', tiles: [33, 34] },
        { id: 'AI', tiles: [25] },
      ],
      current: 0,
      centerTiles: [],
      diceInHand: 0,
      rolled: [],
      setAside: [],
      pickedFaces: [],
      phase: 'over',
    };
    expect(renderGameOver(s, soloView())).toMatchSnapshot();
  });
});
