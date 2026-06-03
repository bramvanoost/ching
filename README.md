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

Four layers, one-way deps. This is the rule that keeps multiplayer and a future mobile/web port a port, not a rewrite.

```
src/engine.ts     pure reducer: (state, action, rng) => newState
src/ai.ts         depends only on engine
src/render.ts     pure: state -> ANSI strings
src/term.ts       terminal I/O (alt-screen, raw mode, animations)
src/cli.ts        thin solo-vs-AI loop
src/client.ts     thin network shell (uses render + term)
src/net/          protocol, daemon, room
```

- **Engine** is pure. No I/O, no `Math.random`, no `Date`. All randomness flows through the injected `rng` so a server can own dice rolls in multiplayer.
- **AI** depends only on the engine.
- **Renderer** is pure. State + viewer perspective in, ANSI strings out. ANSI is emitted unconditionally so snapshot tests are stable across `TERM` and `FORCE_COLOR`.
- **Terminal** owns alt-screen, raw mode, animation pacing. Teardown is idempotent so signal handlers and BYE paths can call it safely.
- **Daemon** is the source of truth in multiplayer: holds room state, calls the engine reducer, owns the RNG (server-authoritative, fair dice). Clients are thin and never run `engine.step` themselves.

## Commands

```
npm run play        # solo vs AI
npm run daemon      # start the multiplayer daemon (unix socket)
npm run join        # connect to the daemon as a player
npm test            # engine + ai + render + protocol + room + client + integration
npm run sim         # 200-game AI-vs-AI regression
```

The regression sim asserts that a higher-discipline AI beats a lower-discipline one over the sample, so AI tiers are never cosmetic.

## Multiplayer on a Raspberry Pi

CHING multiplayer is designed to live on a Pi and be reached over ssh. The daemon process owns every room and every dice roll; clients are thin TUIs that connect over a unix socket.

### Run the daemon

On the Pi (inside `tmux` or `screen` so it survives logout):

```
npm run daemon
```

The daemon listens on `/tmp/ching.sock` (mode `0660`). On startup, if a stale socket file is left over from an unclean restart, the daemon checks whether anything is actually listening; if not, it unlinks the path and rebinds. So a Ctrl-C plus immediate restart is a no-op for the operator. If another daemon is already running, startup fails with a clear error.

### Players connect

Each player sshes into the Pi and runs:

```
npm run join
```

Set `CHING_NAME` to override your display name (defaults to `$USER`). Set `CHING_SOCK` to point at a different socket path. Set `CHING_SESSION` to override the session-token file (defaults to `~/.ching/session.json`); two clients on the same OS account must use separate session files or they'll collide on the same token. Quick local two-client test against a running daemon:

```
CHING_SESSION=/tmp/ching-a.json CHING_NAME=alice npm run join   # terminal A
CHING_SESSION=/tmp/ching-b.json CHING_NAME=bob   npm run join   # terminal B
```

### Lobby flow

- One player picks `[C]reate room` and the daemon mints a 4-char code (letters and digits, excluding the easily-confused `0`, `O`, `I`, `L`, `1`).
- The others pick `[J]oin by code` and type those four characters.
- The host can `[A]dd AI` seats (default discipline `0.6`) to round out the room when only one friend is online.
- Everyone presses `[R]eady`. The host presses `[S]tart`.

### Disconnect and reconnect

- If a player's ssh session drops outside their turn, their seat goes "disconnected" and the game continues unaffected. They can reconnect at any time and reclaim the seat.
- If they drop on their turn, the other players see a 15-second countdown (`AI takes over in 15s…`, then `10s`, `5s`). If they reconnect before the timer expires, control goes back to them with no AI action played. If the timer expires, the AI plays the rest of their turn at `discipline 0.6`.
- Reconnecting during AI takeover is allowed; the AI finishes the current turn and the human resumes at the next turn boundary.
- Identity is bound to an opaque session token, persisted at `~/.ching/session.json`. Names are display-only; the token is what reclaims your seat. Reconnect from a different machine works the same way.

Rooms with no connected humans for 30 minutes (including ones with AI seats actively playing) are reaped. This catches the AFK-and-forgotten case.

### Persistence

There is no persistence in v1. A daemon restart loses all in-flight rooms. The game design (Heckmeck-style burn-on-bust) guarantees games end on the order of minutes, so this trade-off is fine to start with.

## Roadmap

1. Solo vs AI and local pass-and-play. No backend.
2. Same engine on a server (PartyKit, Colyseus, or a Pi over ssh). Server owns the RNG. Disconnect, AI takes the seat.
3. Accounts and leaderboards if retention justifies it.

## Tech

TypeScript strict, vitest, tsx. Engine and AI are framework-free and dependency-free.
