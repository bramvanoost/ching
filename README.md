# CHING

A push-your-luck dice game for the terminal. Collect coins, bank them as tiles, steal rivals' tiles when you hit their exact number. Get greedy and bust, you lose a tile.

80s/8-bit mainframe aesthetic. Signature payoff sound: ka-ching.

(Mechanics inspired by Regenwormen/Heckmeck, reskinned with an original name and theme.)

## Install

```
npm install
```

## Play

```
npm run play
```

For a different difficulty: `npm run play -- --discipline=0.3` (greedier, easier to beat) or `0.9` (more disciplined, harder). Default is `0.6`.

## Controls

Single keypress, no Enter.

| Key       | Action                                                       |
| --------- | ------------------------------------------------------------ |
| `R`       | Roll the dice in your hand                                   |
| `1`-`5`   | Set aside all dice of that face value                        |
| `C`       | Set aside all coins (the `$` face, worth 5)                  |
| `S`       | Stop and try to bank                                         |
| `Q`       | Quit                                                         |

The prompt only shows keys that are legal in the current state.

## How a turn works

1. Press `R` to roll your 8 dice.
2. Pick a face value with `1`-`5` or `C`. All dice of that value get set aside, and you can't pick that face again this turn.
3. Re-roll the remaining dice (`R`) or bank (`S`).
4. To bank, your set-aside must contain at least one coin. Your sum picks the highest center tile less than or equal to that sum, or steals from a rival on an exact match.
5. **Bust** if your next roll lands on no new faces, you stop without a coin, or no tile fits. You lose your top tile, and the highest center tile is burned permanently.

The center starts with tiles 21-36, worth 1, 2, 3, or 4 coins each (40 coins total before any are burned). Most coins when the center empties wins.

## Architecture

Three layers, one-way deps. This is the rule that keeps multiplayer and a future mobile/web port a port, not a rewrite.

```
src/engine.ts  pure reducer: (state, action, rng) => newState
src/ai.ts      depends only on engine
src/cli.ts     swappable renderer; depends on engine + ai
```

- **Engine** is pure. No I/O, no `Math.random`, no `Date`. All randomness flows through the injected `rng` so a server can own dice rolls in multiplayer.
- **AI** depends only on the engine. Decides PICK + STOP/ROLL via a single `discipline` knob: `0` is greedy (holds out for 4-coin tiles, tolerates risky rolls), `1` is cautious (banks any reachable tile, bails early). Higher discipline wins more in regression.
- **Renderer** reads state and sends actions. No game rules live here. The terminal shell uses ANSI 256-color, bevel/shadow panels, and animated spinning coins. A future web or mobile shell would import the same engine + ai.

## Commands

```
npm run play        # play in terminal vs AI
npm test            # engine + AI tests (vitest)
npm run sim         # 200-game AI-vs-AI regression
```

The regression sim asserts that a higher-discipline AI beats a lower-discipline one over the sample, so AI tiers are never cosmetic.

## Roadmap

1. Solo vs AI and local pass-and-play. No backend.
2. Same engine on a server (PartyKit, Colyseus, or a Pi over ssh). Server owns the RNG. Disconnect, AI takes the seat.
3. Accounts and leaderboards if retention justifies it.

## Tech

TypeScript strict, vitest, tsx. Engine and AI are framework-free and dependency-free.
