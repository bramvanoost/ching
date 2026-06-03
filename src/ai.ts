// CHING AI. Depends only on engine. Single discipline knob.
// 0 = greedy: holds out for top-tier tiles, tolerates near-coin-flip busts.
// 1 = cautious: banks any tile, bails at the first whiff of bust risk.
// No I/O. No Math.random/Date.

import {
  COIN,
  FACES,
  faceValue,
  tileCoins,
  type Action,
  type Face,
  type State,
} from './engine.js';

export type Difficulty = { discipline: number };

export function decide(state: State, ai: Difficulty): Action {
  if (state.phase === 'pick') {
    return { type: 'PICK', face: pickFace(state) };
  }
  if (state.setAside.length === 0) return { type: 'ROLL' };
  return continueOrStop(state, ai);
}

function pickFace(state: State): Face {
  const candidates: Face[] = FACES.filter(
    (f) => !state.pickedFaces.includes(f) && state.rolled.includes(f),
  );
  const hasCoin = state.setAside.includes(COIN);
  if (!hasCoin && candidates.includes(COIN)) return COIN;
  const countOf = (f: Face) => state.rolled.filter((d) => d === f).length;
  const valueOf = (f: Face) => countOf(f) * faceValue(f);
  return candidates.reduce((best, f) => (valueOf(f) > valueOf(best) ? f : best), candidates[0]);
}

function continueOrStop(state: State, ai: Difficulty): Action {
  const sum = state.setAside.reduce((acc, f) => acc + faceValue(f), 0);
  const hasCoin = state.setAside.includes(COIN);
  if (!hasCoin) return { type: 'ROLL' };

  const target = bestBankableTile(state, sum);
  if (target === null) return { type: 'ROLL' };

  const pickedCount = state.pickedFaces.length;
  const bustProb = Math.pow(pickedCount / 6, state.diceInHand);

  // Bust tolerance shrinks sharply as discipline rises. Greedy AIs press
  // deep into risky rolls; disciplined AIs bail early.
  const bustCeiling = 0.75 - ai.discipline * 0.6; // 0.75..0.15
  if (bustProb >= bustCeiling) return { type: 'STOP' };

  // Cap target tier by what's still reachable in the center so we don't
  // stall waiting for tiles that no longer exist.
  const ceiling =
    state.centerTiles.length > 0
      ? tileCoins(state.centerTiles[state.centerTiles.length - 1])
      : 4;
  // Discipline narrows ambition: 0 holds out for 4-coin tiles, 1 banks any.
  const desiredTier = Math.max(1, Math.min(ceiling, Math.round(4 - ai.discipline * 3.5)));
  if (tileCoins(target) >= desiredTier) return { type: 'STOP' };

  return { type: 'ROLL' };
}

function bestBankableTile(state: State, sum: number): number | null {
  for (let i = 0; i < state.players.length; i++) {
    if (i === state.current) continue;
    const tiles = state.players[i].tiles;
    if (tiles.length > 0 && tiles[tiles.length - 1] === sum) return sum;
  }
  const available = state.centerTiles.filter((t) => t <= sum);
  if (available.length === 0) return null;
  return Math.max(...available);
}
