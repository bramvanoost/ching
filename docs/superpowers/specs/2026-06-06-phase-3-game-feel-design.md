# CHING iOS Phase 3, Game Feel Design

**Status:** approved for planning
**Date:** 2026-06-06
**Owner:** Bram

## Context

Phase 2 v2 shipped a tappable iOS app: single Game screen, hardcoded 1v1 vs Jones, default SwiftUI styling, no sound, no animations, no settings. During Phase 2 manual testing Bram identified the loudest gap: Jones plays instantly inside a tight `while` loop, so you never *see* an AI turn unfold, and there is no way to tune difficulty or face a different personality. Phase 3 addresses that gap and only that gap.

Phase 3 is gameplay feel. It does not introduce the 1-bit visual system, additional screens, sound, or haptics. Those are deferred to later phases.

## Goals and non-goals

### In Phase 3

- AI turns are paced. A ~300ms delay between each AI action so the player can read the state changing step by step.
- A footer line on the Game screen reads `"<NAME> is thinking…"` while control is on any AI seat, hidden otherwise.
- The cast grows to 1v2: YOU plus Jones plus Bot 03. The Vault row renders three rows. The game over alert ranks all three.
- A segmented Easy / Normal / Hard picker lives at the top of the Game screen. Switching it takes effect on the AI's next decision (current decision in flight is not retroactive). Selection persists across app launches via UserDefaults.
- Pacing honors iOS Reduce Motion. When Reduce Motion is enabled in Settings > Accessibility > Motion, the per-action delay collapses to zero and the game plays through AI turns instantly, same as Phase 2's behaviour but with the footer still indicating whose turn it is.
- The bank/steal label introduced at the end of Phase 2 (`"Bank"` vs `"STEAL FROM <name>"`) continues to work, now against either rival.

### Explicitly out of Phase 3

- 1-bit dither visual system, display serif, stamp buttons, watermark lattice. Default SwiftUI styling continues.
- All non-Game screens (Splash, Home, Receipt, Settings, Onboarding). The Game screen remains the only screen.
- A dedicated Settings sheet. The difficulty picker on the Game screen is the only user-facing toggle.
- Explicit user-facing instant-mode toggle. Reduce Motion is the only way to skip pacing.
- Opponent selection UI. The cast is hardcoded to YOU + Jones + Bot 03 every game.
- Merit (the middle character). Phase 3 ships two opponents, not three. Merit lands when the cast becomes player-selectable.
- Character color dots, name badges, or any chrome beyond the player id string in the Vault row.
- A play log on the Game screen. The footer `"<NAME> is thinking…"` is the only narration.
- Sound and haptics. Both deferred to a later phase.
- Resume-game persistence. Quitting the app still drops the in-progress game. UserDefaults persistence is added only for the difficulty key.

## Visual surface

The Game screen layout from Phase 2 stays. Two additions and one tweak:

```
[Easy | Normal | Hard]          <-- new, segmented picker, top of screen
CHING                            <-- unchanged title
Phase: roll
Turn: YOU
Scores: YOU 0  JONES 0  BOT 03 0   <-- scores list now includes BOT 03
CENTER
[21][22][23]...                  <-- unchanged
VAULTS                           <-- now THREE rows
  YOU     [...]
  JONES   [...]
  BOT 03  [...]
DICE  ...                        <-- unchanged
PICK [1][2][3][4][5][C]          <-- unchanged
[Roll]  [Bank / STEAL FROM ...]  <-- unchanged
JONES is thinking…               <-- new, only when an AI is current
```

The picker uses SwiftUI's default segmented `Picker` styling. The thinking footer uses the default body font. No custom typography, no colour, no icons.

## Game over alert

Phase 2's alert showed `"You win" / "Jones wins" / "Tie"`. Phase 3 generalises to three players and clarifies the tie semantics.

- **Title:** `"Game over"` (unchanged).
- **Message body, line 1:** the winner sentence.
  - Single top scorer: `"<NAME> wins."` (e.g. `"BOT 03 wins."`)
  - Multiple players tied for top: `"Tie at the top."`
- **Message body, line 2:** a ranked score list joined by `" · "` (middle dot), highest first: `"BOT 03 18 · YOU 14 · JONES 12"`.
- **Buttons:** single `"New Game"` button, unchanged behaviour (calls `store.newGame()`).

## Architecture

### Engine

Unchanged. The engine already supports an arbitrary number of players. The Phase 1 port covered N-player steal, bank, bust, and end conditions. Phase 3 adds zero engine code and runs the existing 32 engine tests unchanged.

### `GameStore`

The Phase 2 store is extended, not rewritten. Key additions:

**Difficulty type.** A new `Difficulty` enum:

```swift
enum Difficulty: String, Codable, CaseIterable {
    case easy, normal, hard
    var modifier: Double {
        switch self {
        case .easy: return -0.15
        case .normal: return 0
        case .hard: return 0.15
        }
    }
}
```

**Cast.** The seat constants and player ids expand:

```swift
static let humanSeat = 0
static let jonesSeat = 1
static let bot03Seat = 2

private let baseDiscipline: [Int: Double] = [
    jonesSeat: 0.30,
    bot03Seat: 0.85,
]
```

`initialState(playerIds: ["YOU", "JONES", "BOT 03"])` becomes the new game state in `init` and `newGame()`.

**Difficulty property, persisted.**

```swift
var difficulty: Difficulty {
    didSet {
        UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
    }
}

private static let difficultyKey = "ching.difficulty"

private static func loadDifficulty() -> Difficulty {
    let raw = UserDefaults.standard.string(forKey: difficultyKey) ?? ""
    return Difficulty(rawValue: raw) ?? .normal
}
```

The initializer loads from UserDefaults; the setter writes back.

**Current-seat AI difficulty.**

```swift
private var currentAIDifficulty: CHINGEngine.Difficulty? {
    guard !isHumanTurn else { return nil }
    let base = baseDiscipline[state.current] ?? 0.5
    let adjusted = max(0, min(1, base + difficulty.modifier))
    return CHINGEngine.Difficulty(discipline: adjusted)
}
```

(`CHINGEngine.Difficulty` is the engine's existing single-discipline struct, distinct from this new `Difficulty` enum in the app namespace. The namespace collision is intentional and parallels Phase 2's `SwiftUI.State` vs `CHINGEngine.State` collision.)

**Async AI driver.** Phase 2's synchronous `runAIIfNeeded()` is replaced with an async variant that the view awaits:

```swift
func runAIIfNeeded(reduceMotion: Bool) async {
    while !isOver && !isHumanTurn, let ai = currentAIDifficulty {
        let action = decide(state: state, ai: ai)
        apply(action)
        if !reduceMotion {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}
```

The store remains `@MainActor`. All state mutations happen on the main actor, so SwiftUI observation is consistent.

**`bankActionLabel`** — no code change. The existing implementation iterates rivals in order and returns the first match. With two rivals it naturally handles the multi-AI case and matches the engine's first-in-order steal preference.

### `GameView`

Three additions:

1. **`@Environment(\.accessibilityReduceMotion) var reduceMotion`** at the top of the view. Read on every render and passed into the async AI driver.

2. **`DifficultyPicker` subview** at the top of the screen, above the `CHING` title:

   ```swift
   struct DifficultyPicker: View {
       @Binding var difficulty: Difficulty
       var body: some View {
           Picker("Difficulty", selection: $difficulty) {
               ForEach(Difficulty.allCases, id: \.self) { d in
                   Text(d.rawValue.capitalized).tag(d)
               }
           }
           .pickerStyle(.segmented)
       }
   }
   ```

   Bound to `store.difficulty`. Changes call the `didSet` on the store which persists.

3. **Thinking footer.** Below the `ActionBar`, a conditional `Text("\(currentAIName) is thinking…")` shown only when `!store.isHumanTurn && !store.isOver`. `currentAIName` reads `store.state.players[store.state.current].id`.

4. **Game over alert message** rewritten per the spec above.

The `act` helper changes to wrap the AI driver in a Task so the view can `await`:

```swift
private func act(_ action: Action) {
    store.apply(action)
    Task { await store.runAIIfNeeded(reduceMotion: reduceMotion) }
}
```

`PickBar` and `ActionBar` signatures are unchanged.

### Data flow

```
View tap -> act(Action)
  store.apply(Action)            <-- sync, state mutates, view re-renders
  Task { runAIIfNeeded(...) }    <-- async, may take seconds, each step
                                     re-renders the view
```

The store stays the single source of truth. The View is a thin renderer plus a Task launcher. No new state lives in the View.

### Error handling

There is no new error surface. `Task.sleep` can throw on cancellation; the `try?` suppresses it because cancellation just means the loop exits early (next iteration's condition will re-check and may early-return). UserDefaults reads default to `.normal` on any parse failure.

## Testing

### New `GameStoreTests`

- `test_difficulty_modifierAppliesToBaseDiscipline` — for each seat, `Easy` yields base - 0.15 (clamped), `Normal` yields base, `Hard` yields base + 0.15.
- `test_difficulty_persistsAcrossInstances` — create a store, set Hard, create a fresh store with default init, observe Hard. (Test must clean up UserDefaults in `setUp`/`tearDown` to avoid bleeding into other tests.)
- `test_runAIIfNeeded_reduceMotion_isInstantSequence` — calling `await runAIIfNeeded(reduceMotion: true)` from a state where it is the AI's turn returns in well under one second (no real sleeps), and the resulting state is identical to what the synchronous Phase 2 driver would have produced.
- `test_runAIIfNeeded_normalPacing_isAsync` — calling `await runAIIfNeeded(reduceMotion: false)` from an AI turn takes at least ~300ms × actions for a non-trivial turn (sanity-check that the sleeps are in fact awaited). May use a small action count to keep the test fast.
- `test_threePlayerGameTerminates` — full game with ["YOU", "JONES", "BOT 03"] using `decide` for all three reaches `.over` within a safety limit (5000 actions).
- `test_bankActionLabel_multiAI_pointsAtFirstRivalInOrder` — with both Jones (rival index 1) and Bot 03 (rival index 2) holding a top tile equal to a constructed set-aside sum, the label reads `"STEAL FROM JONES"` (matching the engine's first-in-order preference).

### Existing tests

- Engine tests (32): unchanged, must still pass.
- Phase 2 `GameStoreTests` (5): adjusted in two ways:
  - Any test that calls `store.runAIIfNeeded()` (sync) becomes `await store.runAIIfNeeded(reduceMotion: true)`.
  - `test_init_setsUpTwoPlayersHumanTurnRollPhase` is renamed and updated to assert three players, not two. The new assertions: 3 players, ids `["YOU", "JONES", "BOT 03"]`, scores `[0, 0, 0]`, phase roll, current 0.

Total target: ~11 `GameStoreTests` + 32 engine tests.

### Manual verification

A single playthrough on the simulator covers the smoke surface:

- The picker is visible at the top of the screen, shows three segments, defaults to `Normal` on first launch.
- After tapping `Roll`, picking, and tapping `Bank`, the footer reads `"JONES is thinking…"` while Jones plays. Dice update step by step with visible delay. When control reaches Bot 03 the footer flips to `"BOT 03 is thinking…"`. When control returns to YOU the footer is hidden.
- Tap the picker to switch to `Easy` mid-game. Take another turn. Jones should be observably looser (greedier) on the next AI decision, though variance makes this hard to assert in one turn. (Confirmed in unit tests rather than manually.)
- Quit and relaunch the app. The difficulty picker should still read whatever was last selected.
- Enable Settings > Accessibility > Motion > Reduce Motion in the simulator. Take a turn. The AI footer briefly flashes but the AI's actions all apply instantly. Disable Reduce Motion, take another turn, pacing returns.
- Play to completion. The game over alert headline names the highest scorer (or `"Tie at the top."`), body lists all three ranked scores.

## Definition of done for Phase 3

- Engine tests: 32/32 green, unchanged.
- `GameStoreTests`: all green, including the new tests above.
- `xcodebuild -only-testing:CHINGTests` returns `** TEST SUCCEEDED **`.
- Manual playthrough on the simulator hits every bullet in "Manual verification".
- Branch merged to `main` via PR.
- A proof-of-life screenshot captures a paced AI turn in progress (footer visible naming the AI).

## Risks and open questions

### Resolved during this brainstorm

- Cast: 1v2 with Jones and Bot 03, Merit deferred.
- Difficulty: live segmented picker on Game screen, UserDefaults persisted.
- Pacing: 300ms between AI actions, Reduce Motion collapses to instant.
- Multi-AI steal: existing `bankActionLabel` already correct.
- Game over: ranked, named top scorer or `"Tie at the top."`.

### Genuinely open, deferred to build phase

- The exact pacing constant (300ms) may want a quick tune during manual playthrough. If 300ms feels sluggish or rushed, adjust to taste. Encode as a single constant in `GameStore` so it is one edit.
- The tied-at-top wording can be revisited once the visual system lands; for Phase 3 the literal string `"Tie at the top."` is acceptable.

### Known risks

- **Async test flakiness.** `test_runAIIfNeeded_normalPacing_isAsync` depends on real sleep timing. If CI proves flaky, the assertion can be relaxed to "elapsed time > 0" or removed in favour of unit tests that inject a clock. Phase 3's plan should not over-engineer this.
- **UserDefaults bleed between tests.** Tests that touch the `ching.difficulty` key must reset it in `setUp`. The plan must explicitly call this out so the implementer doesn't ship flaky tests.
- **Reduce Motion behaviour at runtime is not directly testable in unit tests.** The Phase 3 tests cover the `reduceMotion: Bool` parameter path. The actual `@Environment` wiring is covered only by manual verification on the simulator.
