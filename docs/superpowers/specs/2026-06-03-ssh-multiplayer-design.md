# SSH-native multiplayer for CHING

Date: 2026-06-03
Status: Approved (design); pending implementation plan.

## Goal

Make CHING playable by 2–4 humans over ssh into a Raspberry Pi. One long-running game daemon on the Pi owns rooms and is the single source of truth: it holds engine state, calls the existing reducer, and owns the RNG (server-authoritative, fair dice, cheat-proof). Each player sshes into the Pi and runs a thin TUI client that connects to the daemon over a unix domain socket. Local solo-vs-AI play is preserved unchanged.

## Non-goals

- Networking off the Pi (no TCP/TLS, no internet play). Connections are local unix sockets only; ssh provides the network and the authentication shell.
- Accounts, leaderboards, persistence across daemon restarts. Mid-game rooms are lost on restart; that is acceptable for v1 and explicitly out of scope.
- Spectating, replays, chat.
- New gameplay rules. The engine reducer and AI module are untouched.

## Constraints (do not violate)

- `src/engine.ts` and `src/ai.ts` are not modified. Game rules and AI behaviour are bit-for-bit identical to the current main branch.
- All randomness still flows through the injected `rng`. Server is the only thing that supplies it in multiplayer.
- Renderer never imports from `net/`; daemon never imports from `render.ts`/`term.ts`. The two halves share only `engine.ts`, `ai.ts`, and `net/protocol.ts`.
- TypeScript strict, no `any` in engine/ai/render.
- CLI continues to fit the 22-row alt-screen frame discipline documented in `CLAUDE.md`.

## Architecture

Three concerns are split apart: pure rendering, terminal I/O, and the game loop. Two new entry points (daemon and network client) are added alongside the existing solo CLI.

```
src/
  engine.ts          unchanged — pure reducer, N players already supported
  ai.ts              unchanged
  render.ts          NEW — pure state→ANSI string functions
  term.ts            NEW — terminal I/O (alt-screen, raw mode, input queue, drawFrame)
  cli.ts             SLIMMED — thin solo-vs-AI loop using render + term
  client.ts          NEW — network shell (lobby UX + game UX over the socket)
  net/
    protocol.ts      NEW — wire message types, line-delimited JSON encode/decode
    daemon.ts        NEW — server entry, listens on /tmp/ching.sock
    room.ts          NEW — Room class, owns lobby/game state + RNG + grace timers
tests/
  render.test.ts     NEW — snapshot tests on renderFrame
  protocol.test.ts   NEW — encode/decode roundtrip + framing edge cases
  room.test.ts       NEW — lobby, turn enforcement, grace timer cadence, reaper
  client.test.ts     NEW — client reducer + terminal-teardown lifecycle
  integration.test.ts NEW — two in-process clients play a full game via the daemon
```

### Module responsibilities

**`render.ts`** — pure functions, state in, ANSI strings out. No `process.stdout`, no `setTimeout`. Exports:

```ts
renderFrame(state: State, view: ViewOpts): string
renderBoot(): string[]               // typewriter lines
renderGameOver(state: State, view: ViewOpts): string
flashBannerFrames(text: string, color: number): string[]
animateRollFrames(before: State, after: State, view: ViewOpts): string[]
```

The renderer takes a viewer perspective so labels and colors work for any seat count:

```ts
type ViewOpts = {
  viewerSeat: number | null;   // null = solo-vs-AI legacy view
  seats: Array<{
    label: string;             // "YOU" if seat === viewerSeat, else display name
    color: number;             // 256-color id, assigned by the client
    kind: 'human' | 'ai' | 'ai-takeover';
    connected: boolean;        // dim the label if false
  }>;
  footer?: string;
  spinIdx?: number;
  spinFrame?: number;
  spinGlint?: boolean;
};
```

The center-tiles and current-turn panels become viewer-agnostic. The VAULTS panel renders one row per seat in seat order, replacing the current YOU/AI hardcoding. The solo-vs-AI legacy view passes `{viewerSeat: 0, seats: [{label: 'YOU',…}, {label: 'AI (0.6)',…}]}` so the existing look is preserved bit-for-bit (asserted by a render snapshot test).

**`term.ts`** — terminal I/O. Owns alt-screen, raw mode, the input queue, the frame writer, and frame-animation playback (`playFrames(frames, msPerFrame)`). Exposes `setup()`, `teardown()`, `drawFrame(s)`, `waitKey()`, `delay(ms)`. The teardown is idempotent and safe to call from signal handlers.

**`cli.ts`** — thin solo-vs-AI loop. Imports `engine`, `ai`, `render`, `term`. The user-visible behaviour of `npm run play` is unchanged.

**`client.ts`** — network shell. Connects to `/tmp/ching.sock`, sends `HELLO`, drives main menu → lobby → game UX, renders with `render.ts` + `term.ts`. Holds the client reducer that maps `ROOM_STATE`/`GAME_STATE` pushes to `ViewOpts`. The reducer is extracted as a pure function so it can be unit-tested.

**`net/protocol.ts`** — shared wire-type definitions and a `encode(msg)` / `decode(line)` pair. Line-delimited JSON: one message per line, decoder handles partial reads (one JSON split across chunks) and batched reads (multiple JSONs in one chunk). Malformed lines throw a decode error the connection handler turns into an `ERROR` push.

**`net/daemon.ts`** — server entry. Listens on `/tmp/ching.sock` (chmod `0660`). Per-connection async loop reads messages, dispatches into a `Room` if the connection is in one, or into a top-level `Rooms` registry otherwise. Handles `SIGINT`/`SIGTERM` by sending `BYE {reason: "server shutting down"}` to every socket, closing them, and exiting. No state is persisted to disk.

**`net/room.ts`** — `Room` class. Holds:

- Lobby data: `code`, `host`, ordered `seats: SeatRecord[]`, `phase: 'lobby' | 'playing' | 'over'`.
- Game data: engine `State`, server-side `rng = Math.random`.
- Per-seat `SeatConn` (see §Disconnect handling).
- Grace timers and the 30-minute idle reaper.

Methods (all synchronous so they can be driven from tests with a mock clock):

```ts
join(name, token?)  -> { seat, token, kind }
addAiSeat(discipline)
removeSeat(seat)
setReady(seat, ready)
start()
submitAction(seat, action)  // throws NOT_YOUR_TURN if seat !== state.current
detach(seat)                // socket closed
attach(seat, conn)          // reclaimed via reconnect
tick(nowMs)                 // advance timers (grace, reaper)
```

Side effects (`ROOM_STATE`, `GAME_STATE`, `TURN_REMINDER`, `ERROR`, `BYE` pushes) are emitted via an event bus the daemon subscribes to and forwards to the right sockets. Tests subscribe directly to assert the push sequence.

### Boundary discipline

- `render.ts` and `term.ts` never import from `net/`.
- `daemon.ts` and `room.ts` never import from `render.ts` or `term.ts`.
- The only modules shared by both halves are `engine.ts`, `ai.ts`, and `net/protocol.ts`.

## Wire protocol

Transport: unix domain socket at `/tmp/ching.sock`. Line-delimited JSON. Every message is `{ "v": 1, "t": "<type>", ... }`. The `v` byte lets us evolve later without a flag day.

### Client → server

| `t`           | Fields                              | When                                                                |
|---------------|-------------------------------------|---------------------------------------------------------------------|
| `HELLO`       | `{name, token?}`                    | First message. Token, if present, attempts seat reclaim.            |
| `CREATE_ROOM` | `{}`                                | After `HELLO`. Daemon mints a 4-char code from `[A–Z2–9]\{0OIL1}`.  |
| `JOIN_ROOM`   | `{code}`                            | After `HELLO`. Errors if room is full, started, or unknown.         |
| `ADD_AI_SEAT` | `{discipline?}`                     | Host only, lobby only. Default discipline 0.6.                      |
| `REMOVE_SEAT` | `{seat}`                            | Host only, lobby only. Removes an AI seat or kicks a human.         |
| `READY`       | `{ready}`                           | Lobby only. Toggles the caller's own ready flag.                    |
| `START`       | `{}`                                | Host only. Errors if seats < 2 or any human seat isn't ready.       |
| `ACTION`      | `{action: engine.Action}`           | In-game. Daemon validates seat === state.current.                   |
| `LEAVE`       | `{}`                                | Voluntary disconnect.                                               |

### Server → client

| `t`              | Fields                                                             | When                                                                                                            |
|------------------|--------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| `WELCOME`        | `{token, seatHint?: {code, seat}}`                                 | Response to `HELLO`. Always issues a token (new or echoed). `seatHint` set when the token matched a known seat. |
| `ROOM_STATE`     | `{code, host, seats: SeatView[], phase}`                           | Pushed after any lobby or seat-kind change.                                                                     |
| `GAME_STATE`     | `{state: engine.State, viewerSeat, seats: SeatView[], lastEvent?}` | Pushed after every engine step. `lastEvent ∈ {'banked','stolen','busted'}` drives the client's flash effect.    |
| `TURN_REMINDER`  | `{seat, secondsLeft}`                                              | Pushed immediately on active-seat disconnect with `secondsLeft: 15`, then every 5s while the timer counts down. |
| `ERROR`          | `{code, message}`                                                  | Non-fatal protocol error.                                                                                       |
| `BYE`            | `{reason}`                                                         | Daemon closing the connection. Client tears down terminal cleanly on receipt.                                   |

`SeatView` is `{seat, name, kind: 'human'|'ai'|'ai-takeover', ready, connected}`. Colors are not part of the wire protocol; every client derives them deterministically from seat index, so all clients agree without server involvement.

State sync is full-state on every step (small payload, no diffing engine needed). The client diffs `prev` vs `next` locally to drive the existing `effects()` animations.

## Identity, reconnect, and tokens

A player's identity is a name (human-readable) plus an opaque session token. The token is what binds a player to a seat; the name is for display only.

- On the very first `HELLO` without a token, the daemon mints a fresh opaque token (e.g. `crypto.randomUUID()`) and returns it in `WELCOME`. The client persists it at `~/.ching/session.json` keyed by socket path.
- On subsequent `HELLO`s the client presents the token. If it matches a known seat in any room the daemon owns, `WELCOME.seatHint` is set and the client auto-rejoins. Otherwise it's treated as a new identity and a fresh token is issued.
- Tokens are durable across socket disconnects, ssh logouts, and machine changes. Seat number, name, and color stay stable across reconnects.
- Reconnect race (two HELLOs with the same token in the same millisecond): the daemon accepts the most recent connection and sends `BYE {reason: "replaced"}` to the older one.

## Lobby & client UX

### Client startup

`npm run join` runs `tsx src/client.ts`. The client opens the socket, sends `HELLO` with the persisted token (if any), and waits for `WELCOME`.

- `WELCOME.seatHint` present → jump straight into the room. If `phase === 'lobby'` show the lobby screen; if `'playing'` show the game screen.
- Otherwise → show the main menu.

### Main menu

```
   ╔══ CHING · MULTIPLAYER ═══════════════════════════════════╗
   ║                                                          ║
   ║   [C]reate room                                          ║
   ║   [J]oin by code                                         ║
   ║   [Q]uit                                                 ║
   ║                                                          ║
   ╚══════════════════════════════════════════════════════════╝
   > _
```

- `C` → `CREATE_ROOM`. Server replies with `ROOM_STATE` carrying the new code.
- `J` → footer becomes `> code: ____`. Four keystrokes (auto-uppercased, filtered to `[A–Z2–9]`) send `JOIN_ROOM`. Errors come back as `ERROR` and surface in the footer.

### Lobby screen

```
   ╔══ ROOM  X7K3   (host: alice)  ════════════════════════════╗
   ║                                                           ║
   ║   1  alice         ◆  human   ready                       ║
   ║   2  bob           ◆  human   waiting                     ║
   ║   3  AI (0.6)      ◇  ai      ready                       ║
   ║   [+ empty seat]                                          ║
   ║                                                           ║
   ╚═══════════════════════════════════════════════════════════╝
   > [R]eady  [A]dd AI  [K]ick seat  [S]tart  [L]eave  [Q]uit
```

- `R` toggles the caller's own ready flag.
- `A` (host only) → footer prompts for discipline. Single-key shortcuts: `1`=0.2, `2`=0.4, `3`=0.6, `4`=0.8, `Enter`=0.6. Sends `ADD_AI_SEAT`.
- `K` (host only) → footer asks `> seat #:`, sends `REMOVE_SEAT`.
- `S` (host only) → `START`. Greyed when seats < 2 or any human is unready.

The lobby re-renders on every `ROOM_STATE` push.

### Color & label assignment

Every client picks colors from a fixed palette `[Cy_BR, Mg_BR, A_GLINT, P_LIME2]` indexed by seat number, so all clients agree without any server coordination. Your own seat is always labeled `YOU` in your view; other seats use their display name. AI seats are labeled `AI (0.x)`. These mappings live entirely in the client.

### Game screen

When `phase` transitions to `playing`, the client switches to rendering `renderFrame(state, viewOpts)`. From that point:

- On each `GAME_STATE` push, run a local `effects(prev, next)` to play the ka-ching / steal / bust flash. `lastEvent` from the server tells the client which effect to play.
- If `viewerSeat === state.current`, show the prompt footer (`[R]oll [S]top` etc.) and on keypress send `ACTION`. Otherwise show `waiting for <name>…` and ignore game-input keys.
- Roll animation plays on the *receiving* client only — the server does not stream intermediate frames. Other clients see the animation slightly desynced by network latency (microseconds on a local socket).
- `Q` at any point sends `LEAVE` and exits.
- On `TURN_REMINDER`, replace the footer with `> seat <name> disconnected — AI takes over in {secondsLeft}s…`. The `{secondsLeft}` value is interpolated from the message; the very first reminder at t=0 reads `15s`.

### Game over

Server pushes a final `GAME_STATE` with `phase: 'over'`. Client renders the existing `renderGameOver` screen, waits for any key, then exits via the standard teardown path.

## Disconnect, reconnect, AI takeover

Per-seat connection state:

```ts
type SeatConn =
  | { kind: 'live'; socket: ConnRef }
  | { kind: 'down'; sinceMs: number }
  | { kind: 'ai-takeover'; sinceMs: number };
```

`SeatConn` describes whether a *human* seat currently has a live connection. AI seats added by the host are recorded as `kind: 'ai'` in the seat record itself, not via `SeatConn`.

### Lobby drop

Human seat's socket closes while in lobby → flip `SeatConn` to `down`. Seat stays in the room; `ROOM_STATE` re-pushes so other clients see `connected: false`. Reconnect flips it back to `live`. The host can `REMOVE_SEAT` a down seat manually. If the host disconnects, host transfers to the lowest-seat live human; if none, host stays nominal on seat 0 and resumes when someone reconnects.

### In-game drop, not the active seat's turn

Flip `SeatConn` to `down`. Push `ROOM_STATE` so other clients dim the label. Nothing else happens. Game proceeds; the dropped seat's name still appears in vaults. If they reconnect before their turn, no AI ever ran for them.

### In-game drop, the active seat

Start a 15-second grace timer. Flip `SeatConn` to `down`. Immediately push `TURN_REMINDER {seat, secondsLeft: 15}`, then push again at 5s intervals with `secondsLeft: 10`, `5`. Other clients display the countdown by interpolating `secondsLeft` into the footer template.

- Reconnect before t=15s → cancel timer, flip back to `live`, push `GAME_STATE`. No AI ran.
- Timer expires → flip to `ai-takeover`, synthesize actions for that seat using `decide(state, {discipline: 0.6})`. Push `GAME_STATE` after each AI action, paced at 380ms between actions (matches the existing `AI_THINK_MS`).

### Reconnect during `ai-takeover`

Reconnect succeeds, but the AI finishes the current turn. We do not yank control away mid-turn (the human would arrive to a half-formed plan and a possible immediate bust). On the next `endTurn`, the seat flips from `ai-takeover` back to `live`; the prompt routes to the human starting their next turn. Push `ROOM_STATE` to reflect the kind change.

### AI takeover finishes while still disconnected

Once the AI's turn ends (bank, steal, or bust), the seat flips to `down` (not `live`), since the human still isn't connected. Next time their turn comes up, re-enter the grace flow with a fresh 15s timer.

### Paused rooms

If every human seat is non-`live` (all `down` or all `ai-takeover`), the room pauses: the daemon stops synthesizing AI actions until at least one human reconnects. This avoids running games to completion with nobody watching.

### Idle reaper

The reaper rule is independent of pause state. **Any room with zero live human connections for 30 contiguous minutes is reaped**, including paused rooms and rooms with active AI takeover. Sockets receive `BYE {reason: "room reaped"}` and the room is dropped from the registry. An AFK human + AI room does not stay alive forever.

### Reconnect from a different machine

Same token, different socket → works identically. The token is the identity; the socket is just a transport. The `~/.ching/session.json` on the old machine becomes orphaned and is harmless.

### Daemon shutdown

`SIGINT`/`SIGTERM` → push `BYE {reason: "server shutting down"}` to all sockets, close them, exit. No state persisted to disk in v1.

## Client lifecycle: terminal teardown invariant

The client must restore the terminal to cooked mode (exit alt-screen, leave raw mode, show cursor) before exiting under **any** of:

- Voluntary quit (`Q`).
- `BYE` received, any reason (`"replaced"`, `"server shutting down"`, `"room reaped"`, `"kicked"`).
- Socket close without `BYE` (connection error).
- Unhandled error in the client.
- `SIGINT` / `SIGTERM`.

`term.teardown()` is idempotent. The client wires every exit path through a single `shutdown(exitCode)` function that calls `term.teardown()` before `process.exit(exitCode)`. Signal handlers route through the same path. A network flap that delivers `BYE {reason: "replaced"}` and abruptly closes the socket cannot leave a wrecked terminal.

## Server-authoritative RNG

The daemon constructs each room with `rng = Math.random`. The engine reducer is called only on the server. Clients never run `engine.step`. A future swap to a cryptographic source (`crypto.randomInt`) is one line in `room.ts`.

## Daemon lifecycle and deployment

- Launch: `npm run daemon` → `tsx src/net/daemon.ts`. Foreground process; logs structured one-line JSON to stdout (`{ts, level, room?, seat?, msg}`).
- Socket: `/tmp/ching.sock`, mode `0660`. Removed on clean exit.
- On the Pi, run inside `tmux` / `screen`, or wrap in a user-space systemd unit (not shipped in v1; README describes the pattern).
- No persistence. Daemon restart loses all rooms.

## README additions

A new "## Multiplayer on a Raspberry Pi" section will document:

1. Run `npm run daemon` on the Pi (inside `tmux` recommended).
2. Each player `ssh pi@<host>` and runs `npm run join` from a checkout in their home dir (or a shared checkout if they're all on the same shell account).
3. One player picks `[C]reate room` and shares the 4-char code; others `[J]oin by code`.
4. Host can `[A]dd AI` to fill seats; everyone `[R]eady`; host `[S]tart`.
5. Disconnect / reconnect behaviour (15s grace, AI takeover, reclaim with same `~/.ching/session.json`).

## Testing strategy

### Unchanged

`engine.test.ts`, `ai.test.ts`, `sim/regression.ts` are not modified. After the renderer split they must still be green. This is the load-bearing proof that the refactor doesn't change game behaviour.

### New unit tests

- **`tests/render.test.ts`** — snapshot tests on `renderFrame(state, viewOpts)` for ~6 fixed inputs: initial state, mid-roll, pre-bank with coin, pre-bank without coin, 4-seat viewer-is-seat-2, game-over. Snapshots are golden strings under `tests/__snapshots__/`. Pins the visual contract.
- **`tests/protocol.test.ts`** — round-trip every message type through `encode`/`decode`. Framing edge cases: one JSON split across two chunks, multiple JSONs in one chunk, malformed line → throws decode error.
- **`tests/room.test.ts`** — drives `Room` directly with a mock clock and a fake event bus:
  - Lobby: join up to 4, reject 5th. Add AI seat. Kick. Host transfer on host leave. Ready toggle. `START` rejected with <2 seats or unready humans.
  - Turn enforcement: `submitAction(seat, action)` is rejected with `NOT_YOUR_TURN` unless `seat === state.current`.
  - Disconnect grace cadence: drop the active seat. Assert `TURN_REMINDER` pushed at t=0 with `secondsLeft: 15`; at t=5s with `10`; at t=10s with `5`; at t=15s the seat flips to `ai-takeover`, a `GAME_STATE` is pushed instead of further reminders.
  - Reconnect mid-`ai-takeover`: seat stays `ai-takeover` until `endTurn`, then flips to `live`.
  - Reconnect outside the dropped seat's turn: flips straight to `live`, no AI ran.
  - Reconnect token: stale token → fresh token issued; valid token → seat reclaimed; replaced connection receives `BYE {reason: "replaced"}`.
  - Idle reaper: paused room with 1 human + 1 AI seat, drop the human. Advance to 29:59 — alive. Advance to 30:00 — reaped (`code` no longer joinable, `BYE` sent). Repeat with a room mid-`ai-takeover` to prove an actively-playing-but-no-human-watching room reaps.
- **`tests/client.test.ts`** — extracts the client reducer as a pure function and tests it. Also extracts `runClient(conn, term)` so terminal teardown is observable:
  - Reducer: `ROOM_STATE` + `GAME_STATE` produce expected `ViewOpts`; "should I prompt?" returns true iff `viewerSeat === state.current`.
  - BYE teardown: inject a `FakeTerm` recording `setup()`/`teardown()` calls. Drive the client to a setup state, then deliver `BYE {reason: "replaced"}`. Assert `teardown()` called exactly once, exit code 0. Repeat for `"server shutting down"` (exit 0) and abrupt socket close with no `BYE` (exit 1, teardown still called).
  - Signal teardown: send a synthetic `SIGINT` through the client's signal handler. Assert `teardown()` called before `process.exit`.

### New integration test

**`tests/integration.test.ts`** — boots the daemon in-process on a temp socket (`/tmp/ching-test-<pid>.sock`), opens two mock `ClientConn` objects that speak the protocol directly (no `term.ts`), drives them through:

1. Both `HELLO` + `CREATE`/`JOIN`, no AI seats added, both `READY`, host `START`.
2. Alternate `ACTION`s based on `state.current` from the last `GAME_STATE`, using `decide()` as the action source with a seeded RNG injected into the daemon for determinism.
3. Game runs to `phase: 'over'`. Assert both clients received the same final state and a `phase: 'over'` push.

This is the "two local clients can play a full game" gate the milestone requires, runnable in CI.

### Manual verification on macOS (before commit)

1. Terminal A: `npm run daemon`.
2. Terminals B & C: `npm run join`, both create/join the same code, B (host) starts.
3. Play several turns, including a bank and a bust.
4. In terminal B, kill the client (Ctrl-C) during B's turn. Watch C's footer count down 15 → 10 → 5. Verify the *interpolated* number is shown, not a hardcoded "10s". At 15s the AI takes over and plays B's turn. Restart B → seat reclaimed at next turn boundary.
5. From terminal D on the same machine, `npm run join`. Because `~/.ching/session.json` exists, D triggers a reconnect race; B receives `BYE {reason: "replaced"}`. Verify B's terminal is restored to cooked mode (cursor visible, alt-screen gone, typing in the shell echoes normally).
6. Quit cleanly with `Q`. Daemon stays up, ready for new rooms.

### Manual verification on the Pi (post-merge, documented in README)

Same flow with two ssh sessions into the Pi from different machines. Confirms unix socket permissions work for the chosen account model and that the 22-row alt-screen frame fits in a default ssh terminal.

## Definition of done

- `npm test` green, including the new tests.
- `npm run sim` green: regression sim terminates cleanly, higher discipline still beats lower.
- `npm run play` produces a frame-identical solo-vs-AI experience (render snapshot + eyeball).
- `npm run daemon` + two `npm run join` clients can play a full game to completion.
- `grep -E 'Math\.random|Date\.now' src/engine.ts src/ai.ts` returns nothing.
- README has a "Multiplayer on a Raspberry Pi" section.
- Two separate commits: refactor first, daemon + client second.

## Commit split

- **Commit 1**: `refactor: split cli into engine-agnostic renderer (render.ts, term.ts)`. Adds `render.ts` and `term.ts`, slims `cli.ts` to a thin solo-vs-AI loop. Adds `tests/render.test.ts`. **No new gameplay surface area.** Reviewable diff: `cli.ts` shrinks to ~150 lines; the rest moves with minimal rewrites.
- **Commit 2**: `feat: ssh-native multiplayer via daemon + thin client`. Adds `src/net/`, `src/client.ts`, `npm run daemon` and `npm run join` scripts, all networking tests, the README section.
