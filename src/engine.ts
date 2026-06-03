// CHING engine. Pure reducer: (state, action, rng) => newState.
// No I/O. No Math.random/Date. All randomness flows through the injected rng.

export type Face = 1 | 2 | 3 | 4 | 5 | 6;
export const COIN: Face = 6;
export const TOTAL_DICE = 8;

export type Player = {
  id: string;
  tiles: number[];
};

export type Phase = 'roll' | 'pick' | 'over';

export type State = {
  players: Player[];
  current: number;
  centerTiles: number[];
  diceInHand: number;
  rolled: Face[];
  setAside: Face[];
  pickedFaces: Face[];
  phase: Phase;
};

export type Action =
  | { type: 'ROLL' }
  | { type: 'PICK'; face: Face }
  | { type: 'STOP' };

export type Rng = () => number;

const ALL_FACES: readonly Face[] = [1, 2, 3, 4, 5, 6];

export function faceValue(f: Face): number {
  return f === COIN ? 5 : f;
}

export function tileCoins(tile: number): number {
  if (tile <= 24) return 1;
  if (tile <= 28) return 2;
  if (tile <= 32) return 3;
  return 4;
}

export function score(state: State): number[] {
  return state.players.map((p) => p.tiles.reduce((s, t) => s + tileCoins(t), 0));
}

export function initialState(playerIds: string[]): State {
  return {
    players: playerIds.map((id) => ({ id, tiles: [] })),
    current: 0,
    centerTiles: Array.from({ length: 16 }, (_, i) => 21 + i),
    diceInHand: TOTAL_DICE,
    rolled: [],
    setAside: [],
    pickedFaces: [],
    phase: 'roll',
  };
}

export function step(state: State, action: Action, rng: Rng): State {
  if (state.phase === 'over') return state;
  switch (action.type) {
    case 'ROLL':
      return doRoll(state, rng);
    case 'PICK':
      return doPick(state, action.face);
    case 'STOP':
      return doStop(state);
  }
}

function rollDie(rng: Rng): Face {
  const n = Math.floor(rng() * 6) + 1;
  return Math.min(6, Math.max(1, n)) as Face;
}

function doRoll(state: State, rng: Rng): State {
  if (state.phase !== 'roll') return state;
  if (state.diceInHand === 0) return state;
  const rolled: Face[] = Array.from({ length: state.diceInHand }, () => rollDie(rng));
  const hasNewFace = rolled.some((f) => !state.pickedFaces.includes(f));
  if (!hasNewFace) {
    return bust(state);
  }
  return { ...state, rolled, phase: 'pick' };
}

function doPick(state: State, face: Face): State {
  if (state.phase !== 'pick') return state;
  if (state.pickedFaces.includes(face)) return state;
  const taken = state.rolled.filter((f) => f === face);
  if (taken.length === 0) return state;
  const next: State = {
    ...state,
    setAside: [...state.setAside, ...taken],
    pickedFaces: [...state.pickedFaces, face],
    diceInHand: state.diceInHand - taken.length,
    rolled: [],
    phase: 'roll',
  };
  // If you've used all 8 dice, you must stop and try to bank.
  if (next.diceInHand === 0) {
    return tryBank(next);
  }
  return next;
}

function doStop(state: State): State {
  if (state.phase !== 'roll') return state;
  if (state.setAside.length === 0) return state;
  return tryBank(state);
}

function tryBank(state: State): State {
  const sum = state.setAside.reduce((acc, f) => acc + faceValue(f), 0);
  const hasCoin = state.setAside.includes(COIN);
  if (!hasCoin) return bust(state);

  // Steal: exact match on a rival's top tile.
  for (let i = 0; i < state.players.length; i++) {
    if (i === state.current) continue;
    const tiles = state.players[i].tiles;
    if (tiles.length === 0) continue;
    if (tiles[tiles.length - 1] === sum) {
      const players = state.players.map((p, idx) => {
        if (idx === i) return { ...p, tiles: p.tiles.slice(0, -1) };
        if (idx === state.current) return { ...p, tiles: [...p.tiles, sum] };
        return p;
      });
      return endTurn({ ...state, players });
    }
  }

  // Center: take the highest tile <= sum.
  const available = state.centerTiles.filter((t) => t <= sum);
  if (available.length === 0) return bust(state);
  const taken = Math.max(...available);
  const centerTiles = state.centerTiles.filter((t) => t !== taken);
  const players = state.players.map((p, i) =>
    i === state.current ? { ...p, tiles: [...p.tiles, taken] } : p,
  );
  return endTurn({ ...state, players, centerTiles });
}

function bust(state: State): State {
  let players = state.players;
  let centerTiles = state.centerTiles;
  const me = state.players[state.current];
  if (me.tiles.length > 0) {
    const top = me.tiles[me.tiles.length - 1];
    players = state.players.map((p, i) =>
      i === state.current ? { ...p, tiles: p.tiles.slice(0, -1) } : p,
    );
    centerTiles = [...centerTiles, top].sort((a, b) => a - b);
  }
  // Burn the highest remaining center tile so the supply depletes.
  if (centerTiles.length > 0) {
    centerTiles = centerTiles.slice(0, -1);
  }
  return endTurn({ ...state, players, centerTiles });
}

function endTurn(state: State): State {
  if (state.centerTiles.length === 0) {
    return { ...state, phase: 'over', rolled: [], setAside: [], pickedFaces: [], diceInHand: 0 };
  }
  return {
    ...state,
    current: (state.current + 1) % state.players.length,
    diceInHand: TOTAL_DICE,
    rolled: [],
    setAside: [],
    pickedFaces: [],
    phase: 'roll',
  };
}

// Exhaustiveness aid for ai.ts.
export const FACES = ALL_FACES;
