// 200-game AI-vs-AI regression. Verifies the game terminates and that
// a higher discipline tier beats a lower one over the sample.

import { initialState, step, score, type Rng } from '../src/engine.js';
import { decide } from '../src/ai.js';

function mulberry32(seed: number): Rng {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const GAMES = 200;
const DISC_LOW = 0.2;
const DISC_HIGH = 0.8;
const MAX_STEPS = 50_000;

let lowWins = 0;
let highWins = 0;
let ties = 0;
let totalSteps = 0;

for (let g = 0; g < GAMES; g++) {
  const rng = mulberry32(g + 1);
  // Alternate seats so first-mover advantage doesn't skew the result.
  const playerDisc = g % 2 === 0 ? [DISC_LOW, DISC_HIGH] : [DISC_HIGH, DISC_LOW];

  let state = initialState(['P0', 'P1']);
  let steps = 0;
  while (state.phase !== 'over') {
    if (steps++ >= MAX_STEPS) {
      console.error(`game ${g}: exceeded ${MAX_STEPS} steps without terminating`);
      process.exit(1);
    }
    const discipline = playerDisc[state.current];
    state = step(state, decide(state, { discipline }), rng);
  }
  totalSteps += steps;

  const scores = score(state);
  const lowScore = playerDisc[0] === DISC_LOW ? scores[0] : scores[1];
  const highScore = playerDisc[0] === DISC_LOW ? scores[1] : scores[0];
  if (highScore > lowScore) highWins++;
  else if (lowScore > highScore) lowWins++;
  else ties++;
}

console.log(`games:            ${GAMES}`);
console.log(`avg steps:        ${(totalSteps / GAMES).toFixed(1)}`);
console.log(`discipline ${DISC_LOW.toFixed(1)} wins: ${lowWins}`);
console.log(`discipline ${DISC_HIGH.toFixed(1)} wins: ${highWins}`);
console.log(`ties:             ${ties}`);

if (highWins <= lowWins) {
  console.error(
    `FAIL: higher discipline (${highWins}) did not beat lower discipline (${lowWins})`,
  );
  process.exit(1);
}
console.log('OK: higher discipline beats lower discipline');
