# CHING iOS Phase 3 — Game Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gameplay feel to the Phase 2 minimum-playable app: paced AI turns, a second opponent (Bot 03), a live Easy/Normal/Hard difficulty picker, UserDefaults persistence for difficulty, iOS Reduce Motion support, and a 3-way game over alert. Engine untouched. Default SwiftUI styling preserved.

**Architecture:** Phase 2's `GameStore` is extended in-place with an app-local `Difficulty` enum, a per-seat base-discipline dictionary, UserDefaults persistence, and an async `runAIIfNeeded(reduceMotion:)` driver. The single Phase 2 `GameView` grows a top-of-screen segmented picker, a conditional thinking footer, and a 3-way ranked game over alert. No engine changes. No new screens.

**Tech Stack:** Swift 5.10 / SwiftUI / iOS 17+, `@Observable` macro, XCTest, `UserDefaults`, `@Environment(\.accessibilityReduceMotion)`, `Task.sleep` for pacing.

---

## Spec reference (do not re-derive)

Full design at `docs/superpowers/specs/2026-06-06-phase-3-game-feel-design.md`. Key facts the plan assumes:

- Cast = 3 players in fixed order: `["YOU", "JONES", "BOT 03"]` (seats 0, 1, 2).
- Base discipline per AI seat: Jones = 0.30, Bot 03 = 0.85.
- Difficulty modifier: Easy = -0.15, Normal = 0, Hard = +0.15. Effective discipline is clamped to `[0, 1]`.
- Pacing: `Task.sleep` for **300,000,000 ns** (300ms) between each AI action.
- UserDefaults key: `"ching.difficulty"`, value is the raw string of the `Difficulty` enum.
- Reduce Motion collapses the 300ms sleep to zero, footer still appears (briefly).
- Game over alert headline: `"<NAME> wins."` or `"Tie at the top."` if multiple top. Body: ranked list joined by ` · `.

The new app-local `Difficulty` enum lives in `GameStore.swift` and namespace-collides with `CHINGEngine.Difficulty` (the engine's single-discipline struct). This is intentional. Where both are in scope (the AI driver builds an engine-Difficulty from the app-Difficulty + base discipline), use fully qualified `CHINGEngine.Difficulty(discipline: ...)`. Parallels Phase 2's `@SwiftUI.State` workaround.

---

## File structure

After this plan completes, file diffs land in:

```
ios/CHING/CHING/
├── GameStore.swift              # Phase 2 file, extended (Tasks 1, 2, 3, 4)
├── GameView.swift               # Phase 2 file, extended (Tasks 3, 6, 7, 8, 9)
└── (everything else untouched)

ios/CHING/CHINGTests/
└── GameStoreTests.swift         # Phase 2 file, adjusted + new tests (Tasks 1, 2, 3, 4, 5)

docs/superpowers/
└── 2026-06-06-phase-3-screenshot.png   # Task 10
```

No new files in `ios/CHING/CHING/`. The existing single-file pattern (one `GameStore.swift`, one `GameView.swift` containing all view types) continues. A split into per-component files is Phase 4+ work when the visual system lands.

---

## Test command reference

Throughout, the canonical test command is (keep `-only-testing:CHINGTests` — running the auto-generated `CHINGUITests` target adds ~6 minutes per cycle and we do not need it):

```bash
cd /Users/bramvanoost/Code/game-ching && xcodebuild test \
  -project ios/CHING/CHING.xcodeproj \
  -scheme CHING \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:CHINGTests \
  2>&1 | grep -E "Test Case|passed|failed|TEST" | tail -20
```

Canonical build command (no tests):

```bash
cd /Users/bramvanoost/Code/game-ching && xcodebuild \
  -project ios/CHING/CHING.xcodeproj \
  -scheme CHING \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Canonical install + launch:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name CHING.app -path "*Debug-iphonesimulator*" -print -quit)
xcrun simctl install booted "$APP_PATH"
xcrun simctl terminate booted com.fastronaut.CHING 2>/dev/null
xcrun simctl launch booted com.fastronaut.CHING
```

If the simulator isn't booted yet:

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
```

---

## Task 1: Add `Difficulty` enum and modifier math

**Files:**
- Modify: `ios/CHING/CHING/GameStore.swift`
- Modify: `ios/CHING/CHINGTests/GameStoreTests.swift`

Add a new app-local `Difficulty` enum at the top of `GameStore.swift` (above the `GameStore` class). Add a test that locks the modifier table.

- [ ] **Step 1: Write the failing test**

Append to `ios/CHING/CHINGTests/GameStoreTests.swift`, just before the closing `}` of the class:

```swift
    func test_difficulty_modifierTable() {
        XCTAssertEqual(Difficulty.easy.modifier, -0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.normal.modifier, 0, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.hard.modifier, 0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.allCases, [.easy, .normal, .hard])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run the canonical test command. Expected: failure compiling `GameStoreTests.swift` (`Difficulty` ambiguous because only `CHINGEngine.Difficulty` is currently in the `CHING` module's namespace, and the engine `Difficulty` has no `.easy/.normal/.hard/.modifier/.allCases`).

- [ ] **Step 3: Add the enum**

Insert at the top of `ios/CHING/CHING/GameStore.swift`, between the `import` lines and `@MainActor`:

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

- [ ] **Step 4: Run test to verify it passes**

Run the canonical test command. Expected: all existing tests plus the new `test_difficulty_modifierTable` pass. The 5 Phase 2 tests remain green.

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: Difficulty enum with easy/normal/hard modifier table"
```

---

## Task 2: UserDefaults-backed `difficulty` property on `GameStore`

**Files:**
- Modify: `ios/CHING/CHING/GameStore.swift`
- Modify: `ios/CHING/CHINGTests/GameStoreTests.swift`

Add a `difficulty` property to `GameStore` that reads from UserDefaults on init and writes back via `didSet`. Test the round-trip with an isolated test suite.

- [ ] **Step 1: Add `setUp`/`tearDown` to the test class for UserDefaults isolation**

Edit `ios/CHING/CHINGTests/GameStoreTests.swift`. Replace the class opening from:

```swift
@MainActor
final class GameStoreTests: XCTestCase {
    func test_init_setsUpTwoPlayersHumanTurnRollPhase() {
```

to:

```swift
@MainActor
final class GameStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        super.tearDown()
    }

    func test_init_setsUpTwoPlayersHumanTurnRollPhase() {
```

- [ ] **Step 2: Write the failing test**

Append to `ios/CHING/CHINGTests/GameStoreTests.swift`, before the closing `}`:

```swift
    func test_difficulty_defaultIsNormalOnFirstLaunch() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.difficulty, .normal)
    }

    func test_difficulty_persistsAcrossInstances() {
        let store1 = GameStore(seed: 1)
        store1.difficulty = .hard
        let store2 = GameStore(seed: 2)
        XCTAssertEqual(store2.difficulty, .hard)
    }
```

- [ ] **Step 3: Run tests, watch them fail**

Run the canonical test command. Expected: `test_difficulty_defaultIsNormalOnFirstLaunch` and `test_difficulty_persistsAcrossInstances` fail to compile (`difficulty` is not a member of `GameStore`).

- [ ] **Step 4: Add the property**

In `ios/CHING/CHING/GameStore.swift`, change the `GameStore` class body. Replace the existing `aiDifficulty` line:

```swift
    private let aiDifficulty = Difficulty(discipline: 0.30)
```

with the new persisted property and helpers (also delete the `aiDifficulty` line entirely; the engine-difficulty is now derived per-seat in Task 3):

```swift
    private static let difficultyKey = "ching.difficulty"

    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
    }
```

Then change `init(seed:)` from:

```swift
    init(seed: UInt32) {
        self.rng = Mulberry32(seed: seed)
        self.state = initialState(playerIds: ["YOU", "JONES"])
    }
```

to:

```swift
    init(seed: UInt32) {
        self.rng = Mulberry32(seed: seed)
        self.state = initialState(playerIds: ["YOU", "JONES"])
        let raw = UserDefaults.standard.string(forKey: Self.difficultyKey) ?? ""
        self.difficulty = Difficulty(rawValue: raw) ?? .normal
    }
```

Also temporarily replace the body of `runAIIfNeeded` so the file still compiles before Task 4 lands the async refactor:

```swift
    func runAIIfNeeded() {
        let engineAI = CHINGEngine.Difficulty(discipline: 0.30)
        while !isOver && !isHumanTurn {
            let action = decide(state: state, ai: engineAI)
            apply(action)
        }
    }
```

(That `0.30` literal is the Phase 2 Jones discipline and is deliberately ugly. Task 3 replaces it with the per-seat lookup.)

- [ ] **Step 5: Run tests, watch them pass**

Run the canonical test command. Expected: all existing tests plus the two new difficulty tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: GameStore.difficulty backed by UserDefaults"
```

---

## Task 3: Expand cast to 3 players (YOU + Jones + Bot 03)

**Files:**
- Modify: `ios/CHING/CHING/GameStore.swift`
- Modify: `ios/CHING/CHING/GameView.swift`
- Modify: `ios/CHING/CHINGTests/GameStoreTests.swift`

Replace the hardcoded `["YOU", "JONES"]` with `["YOU", "JONES", "BOT 03"]` in both `init` and `newGame`. Add a per-seat base discipline dictionary. Add a `currentAIDifficulty` helper that combines per-seat base + persisted difficulty modifier. Update the Phase 2 `Scores:` line in `GameView` to render all three. Update Phase 2 tests that hardcoded 2 players.

- [ ] **Step 1: Update Phase 2 tests for the 3-player cast**

In `ios/CHING/CHINGTests/GameStoreTests.swift`, replace `test_init_setsUpTwoPlayersHumanTurnRollPhase`:

```swift
    func test_init_setsUpTwoPlayersHumanTurnRollPhase() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.state.players.count, 2)
        XCTAssertEqual(store.state.players[0].id, "YOU")
        XCTAssertEqual(store.state.players[1].id, "JONES")
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.current, 0)
        XCTAssertTrue(store.isHumanTurn)
        XCTAssertFalse(store.isOver)
        XCTAssertEqual(store.scores, [0, 0])
    }
```

with:

```swift
    func test_init_setsUpThreePlayersHumanTurnRollPhase() {
        let store = GameStore(seed: 1)
        XCTAssertEqual(store.state.players.count, 3)
        XCTAssertEqual(store.state.players[0].id, "YOU")
        XCTAssertEqual(store.state.players[1].id, "JONES")
        XCTAssertEqual(store.state.players[2].id, "BOT 03")
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.current, 0)
        XCTAssertTrue(store.isHumanTurn)
        XCTAssertFalse(store.isOver)
        XCTAssertEqual(store.scores, [0, 0, 0])
    }
```

And replace `test_newGame_resetsState`:

```swift
    func test_newGame_resetsState() {
        let store = GameStore(seed: 1)
        store.apply(.roll)
        store.newGame()
        XCTAssertEqual(store.state.centerTiles, Array(21...36))
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.players[0].tiles, [])
        XCTAssertEqual(store.state.players[1].tiles, [])
        XCTAssertEqual(store.state.current, 0)
    }
```

with:

```swift
    func test_newGame_resetsState() {
        let store = GameStore(seed: 1)
        store.apply(.roll)
        store.newGame()
        XCTAssertEqual(store.state.centerTiles, Array(21...36))
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.players[0].tiles, [])
        XCTAssertEqual(store.state.players[1].tiles, [])
        XCTAssertEqual(store.state.players[2].tiles, [])
        XCTAssertEqual(store.state.current, 0)
    }
```

- [ ] **Step 2: Run tests, watch them fail**

Run the canonical test command. Expected: the two renamed/updated tests fail because `players.count` is still 2.

- [ ] **Step 3: Add cast + per-seat discipline + currentAIDifficulty in `GameStore`**

In `ios/CHING/CHING/GameStore.swift`, replace the seat constants block:

```swift
    static let humanSeat = 0
    static let aiSeat = 1
```

with:

```swift
    static let humanSeat = 0
    static let jonesSeat = 1
    static let bot03Seat = 2

    private let baseDiscipline: [Int: Double] = [
        jonesSeat: 0.30,
        bot03Seat: 0.85,
    ]
```

Replace `init(seed:)` body's `initialState` call:

```swift
        self.state = initialState(playerIds: ["YOU", "JONES"])
```

with:

```swift
        self.state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
```

Replace `newGame` body's `initialState` call (same substitution).

Add a `currentAIDifficulty` computed property below `canPick`:

```swift
    var currentAIDifficulty: CHINGEngine.Difficulty? {
        guard !isHumanTurn else { return nil }
        let base = baseDiscipline[state.current] ?? 0.5
        let adjusted = max(0, min(1, base + difficulty.modifier))
        return CHINGEngine.Difficulty(discipline: adjusted)
    }
```

Replace the temporary `runAIIfNeeded` from Task 2 with one that uses the helper:

```swift
    func runAIIfNeeded() {
        while !isOver, let ai = currentAIDifficulty {
            let action = decide(state: state, ai: ai)
            apply(action)
        }
    }
```

- [ ] **Step 4: Generalize the `Scores:` line in `GameView`**

In `ios/CHING/CHING/GameView.swift`, replace:

```swift
            Text("Scores: YOU \(store.scores[0])  JONES \(store.scores[1])")
```

with:

```swift
            Text("Scores: " + zip(store.state.players, store.scores)
                .map { "\($0.id) \($1)" }
                .joined(separator: "  "))
```

- [ ] **Step 5: Run tests + build, watch them pass**

Run the canonical test command, then the canonical build command. Expected: all tests pass, build succeeds.

- [ ] **Step 6: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHING/GameView.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: cast expands to 3 players (YOU + JONES + BOT 03)"
```

---

## Task 4: Async `runAIIfNeeded(reduceMotion:)`

**Files:**
- Modify: `ios/CHING/CHING/GameStore.swift`
- Modify: `ios/CHING/CHING/GameView.swift`
- Modify: `ios/CHING/CHINGTests/GameStoreTests.swift`

Replace the sync `runAIIfNeeded()` with an async variant. View call sites and one Phase 2 test update accordingly. The 300ms pacing constant lives in `GameStore.swift` as a private static.

- [ ] **Step 1: Update the Phase 2 AI test to await**

In `ios/CHING/CHINGTests/GameStoreTests.swift`, replace `test_runAIIfNeeded_isNoOpOnHumanTurn`:

```swift
    func test_runAIIfNeeded_isNoOpOnHumanTurn() {
        let store = GameStore(seed: 1)
        let before = store.state
        store.runAIIfNeeded()
        XCTAssertEqual(store.state, before)
    }
```

with:

```swift
    func test_runAIIfNeeded_isNoOpOnHumanTurn() async {
        let store = GameStore(seed: 1)
        let before = store.state
        await store.runAIIfNeeded(reduceMotion: true)
        XCTAssertEqual(store.state, before)
    }
```

- [ ] **Step 2: Add a reduce-motion fast-path test**

Append to the same test file before the closing `}`:

```swift
    func test_runAIIfNeeded_reduceMotionRunsInstantly() async {
        let store = GameStore(seed: 1)
        // Force AI's turn by playing a deterministic action sequence.
        // The fastest forced bank-or-bust is hard to construct, so instead
        // we manipulate via a sequence and rely on runAIIfNeeded to return
        // promptly.
        store.apply(.roll)
        // After the human's first roll, state.phase may be .pick. Run pick to
        // force the simplest progression; ignore that runAIIfNeeded will only
        // act when it's an AI's turn.
        let start = Date()
        await store.runAIIfNeeded(reduceMotion: true)
        let elapsed = Date().timeIntervalSince(start)
        // With reduceMotion=true and possibly no AI turn to drive, this
        // should return in under a second comfortably.
        XCTAssertLessThan(elapsed, 1.0)
    }
```

- [ ] **Step 3: Run tests, watch them fail**

Run the canonical test command. Expected: compile failure because `runAIIfNeeded` is still sync and the new tests await.

- [ ] **Step 4: Replace the sync driver with the async one**

In `ios/CHING/CHING/GameStore.swift`, replace:

```swift
    func runAIIfNeeded() {
        while !isOver, let ai = currentAIDifficulty {
            let action = decide(state: state, ai: ai)
            apply(action)
        }
    }
```

with:

```swift
    private static let aiPaceNanoseconds: UInt64 = 300_000_000

    func runAIIfNeeded(reduceMotion: Bool) async {
        while !isOver, let ai = currentAIDifficulty {
            let action = decide(state: state, ai: ai)
            apply(action)
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: Self.aiPaceNanoseconds)
            }
        }
    }
```

- [ ] **Step 5: Update the view to call the async variant**

In `ios/CHING/CHING/GameView.swift`, replace:

```swift
    private func act(_ action: Action) {
        store.apply(action)
        store.runAIIfNeeded()
    }
```

with (note: the `reduceMotion` Bool will be wired through `@Environment` in Task 8; for now pass `false` so pacing is on by default):

```swift
    private func act(_ action: Action) {
        store.apply(action)
        Task { await store.runAIIfNeeded(reduceMotion: false) }
    }
```

- [ ] **Step 6: Run tests + build, watch them pass**

Run the canonical test command, then the canonical build command. Expected: all tests pass, build succeeds.

- [ ] **Step 7: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHING/GameView.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: async runAIIfNeeded with 300ms pacing"
```

---

## Task 5: Multi-AI tests (bank label + 3-player termination)

**Files:**
- Modify: `ios/CHING/CHINGTests/GameStoreTests.swift`

Two new tests. The first replaces the Phase 2 `test_fullGameTerminates` (which hardcoded 2 players via `decide` over a single discipline) with a 3-player variant. The second locks the multi-rival steal-label ordering.

- [ ] **Step 1: Update the existing termination test for 3 players**

Replace `test_fullGameTerminates`:

```swift
    func test_fullGameTerminates() {
        let store = GameStore(seed: 1)
        var safetyLimit = 5000
        while !store.isOver && safetyLimit > 0 {
            let action = decide(state: store.state, ai: Difficulty(discipline: 0.5))
            store.apply(action)
            safetyLimit -= 1
        }
        XCTAssertTrue(store.isOver, "Game should terminate within 5000 actions")
        XCTAssertGreaterThan(safetyLimit, 0)
    }
```

with (the engine `Difficulty` is referenced fully qualified because the app-local `Difficulty` enum now occupies the bare name):

```swift
    func test_fullThreePlayerGameTerminates() {
        let store = GameStore(seed: 1)
        var safetyLimit = 5000
        while !store.isOver && safetyLimit > 0 {
            let action = decide(state: store.state, ai: CHINGEngine.Difficulty(discipline: 0.5))
            store.apply(action)
            safetyLimit -= 1
        }
        XCTAssertTrue(store.isOver, "3-player game should terminate within 5000 actions")
        XCTAssertGreaterThan(safetyLimit, 0)
        XCTAssertEqual(store.state.players.count, 3)
    }
```

- [ ] **Step 2: Add the multi-AI bank label ordering test**

Append before the closing `}`:

```swift
    func test_bankActionLabel_pointsAtFirstRivalWithMatchingTop() {
        let store = GameStore(seed: 1)
        // Construct a state where both rivals (Jones, Bot 03) have a top
        // tile equal to a contrived set-aside sum. The engine's steal logic
        // iterates rivals in player order and picks the first match, so the
        // label must agree.
        var s = store.state
        s.players[1].tiles = [25]     // Jones top = 25
        s.players[2].tiles = [25]     // Bot 03 top = 25
        s.setAside = [.five, .coin, .five, .four, .three, .three]
        s.pickedFaces = [.five, .coin, .four, .three]
        s.diceInHand = 2
        s.phase = .roll
        s.current = GameStore.humanSeat
        store.setStateForTesting(s)
        XCTAssertEqual(store.setAsideSum, 25)
        XCTAssertEqual(store.bankActionLabel, "STEAL FROM JONES")
    }
```

- [ ] **Step 3: Add the test seam to `GameStore`**

The new test mutates a constructed state directly. Add a tiny test seam at the bottom of the `GameStore` class in `ios/CHING/CHING/GameStore.swift`, just before the closing `}`:

```swift
    #if DEBUG
    func setStateForTesting(_ s: State) {
        self.state = s
    }
    #endif
```

Wrapping it in `#if DEBUG` keeps it out of release builds. The `CHINGTests` target compiles in DEBUG configuration so the seam is visible.

- [ ] **Step 4: Run tests, watch them pass**

Run the canonical test command. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameStore.swift ios/CHING/CHINGTests/GameStoreTests.swift && \
  git commit -m "ios: tests for 3-player termination and multi-rival steal label"
```

---

## Task 6: `DifficultyPicker` subview at top of Game screen

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`

Add a new `DifficultyPicker` view bound to `store.difficulty`. Insert it at the top of `GameView.body`, above the `CHING` title.

- [ ] **Step 1: Add the `DifficultyPicker` subview**

Append to `ios/CHING/CHING/GameView.swift`, just above the existing `#Preview {` block:

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

- [ ] **Step 2: Wire it at the top of `GameView.body`**

In `ios/CHING/CHING/GameView.swift`, replace the opening of `body`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHING")
                .font(.largeTitle)
                .bold()
```

with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DifficultyPicker(difficulty: Binding(
                get: { store.difficulty },
                set: { store.difficulty = $0 }
            ))

            Text("CHING")
                .font(.largeTitle)
                .bold()
```

- [ ] **Step 3: Build and re-launch**

Run the canonical build command + the install/launch chain.

Expected: simulator shows a `[ Easy | Normal | Hard ]` segmented picker at the top, with `Normal` selected by default. Tapping `Hard` updates the highlight. Quit and relaunch (`xcrun simctl terminate ...` then `launch`); `Hard` is still selected. (Cold-quit-and-relaunch is the only path that exercises UserDefaults; the `install` step is in-place and preserves state. To test the actual cold-start path, run the install command, then the launch command — already what the canonical chain does.)

- [ ] **Step 4: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: segmented difficulty picker top of Game screen"
```

---

## Task 7: Thinking footer + AI turn naming

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`

Add a footer line below the action bar that reads `"<NAME> is thinking…"` while it's an AI's turn (and the game isn't over). Hidden otherwise.

- [ ] **Step 1: Add a `currentSeatName` helper to `GameView`**

In `ios/CHING/CHING/GameView.swift`, insert above `private var gameOverMessage: String`:

```swift
    private var currentSeatName: String {
        store.state.players[store.state.current].id
    }
```

- [ ] **Step 2: Add the footer below `ActionBar` and inside the main `VStack`**

In `body`, replace:

```swift
            PickBar(store: store, act: act)
            ActionBar(store: store, act: act)

            Spacer()
        }
```

with:

```swift
            PickBar(store: store, act: act)
            ActionBar(store: store, act: act)

            if !store.isHumanTurn && !store.isOver {
                Text("\(currentSeatName) is thinking…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
```

- [ ] **Step 3: Build and re-launch**

Run the canonical build + install + launch chain.

Expected: with the human as starting seat, the footer is absent. After tapping Roll → picking a face with a coin → tapping Bank, control flips to Jones, the footer reads `"JONES is thinking…"` for ~600ms (Jones typically takes 2 actions before banking or busting at the default discipline), then flips to `"BOT 03 is thinking…"` while Bot 03 plays, then disappears when control returns to YOU.

- [ ] **Step 4: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: thinking footer naming the active AI"
```

---

## Task 8: Reduce Motion environment hook

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`

Replace the hardcoded `reduceMotion: false` from Task 4 with the live `@Environment(\.accessibilityReduceMotion)` value, so toggling iOS Settings > Accessibility > Motion > Reduce Motion instantly changes pacing.

- [ ] **Step 1: Add the environment property and use it in `act`**

In `ios/CHING/CHING/GameView.swift`, insert below the `@SwiftUI.State private var store = GameStore()` line:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Then replace:

```swift
    private func act(_ action: Action) {
        store.apply(action)
        Task { await store.runAIIfNeeded(reduceMotion: false) }
    }
```

with:

```swift
    private func act(_ action: Action) {
        store.apply(action)
        let reduce = reduceMotion
        Task { await store.runAIIfNeeded(reduceMotion: reduce) }
    }
```

(The `let reduce = reduceMotion` captures the value on the main actor before launching the Task, avoiding any actor-isolation warnings on the environment access inside the Task body.)

- [ ] **Step 2: Build and re-launch**

Run the canonical build + install + launch chain.

Expected: app launches normally. To test the Reduce Motion path:

1. In the simulator menu: `Features > Toggle Appearance` — no, that's appearance. For Reduce Motion:
2. In the simulator iOS Settings app: `Settings > Accessibility > Motion > Reduce Motion`, toggle on.
3. Switch back to CHING.
4. Tap Roll, pick a face, tap Bank. The AI's actions should apply instantly with no visible pacing; the thinking footer flashes briefly but does not linger 300ms per action.
5. Toggle Reduce Motion off; pacing returns.

(Manual verification only — unit-testing `@Environment` requires UI tests, which are out of scope.)

- [ ] **Step 3: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: honor iOS Reduce Motion to skip AI pacing"
```

---

## Task 9: 3-way game over alert

**Files:**
- Modify: `ios/CHING/CHING/GameView.swift`

Rewrite `gameOverMessage` to rank all three players and pick the winner (or `"Tie at the top."`).

- [ ] **Step 1: Replace `gameOverMessage`**

In `ios/CHING/CHING/GameView.swift`, replace:

```swift
    private var gameOverMessage: String {
        let scores = store.scores
        let you = scores[0]
        let jones = scores[1]
        let outcome: String
        if you > jones { outcome = "You win" }
        else if jones > you { outcome = "Jones wins" }
        else { outcome = "Tie" }
        return "\(outcome).\nYOU \(you)  JONES \(jones)"
    }
```

with:

```swift
    private var gameOverMessage: String {
        let ranked = zip(store.state.players, store.scores)
            .map { (id: $0.id, score: $1) }
            .sorted { $0.score > $1.score }

        let top = ranked.first!.score
        let leaders = ranked.filter { $0.score == top }

        let headline: String
        if leaders.count == 1 {
            headline = "\(leaders[0].id) wins."
        } else {
            headline = "Tie at the top."
        }

        let body = ranked
            .map { "\($0.id) \($0.score)" }
            .joined(separator: " · ")

        return "\(headline)\n\(body)"
    }
```

- [ ] **Step 2: Build and re-launch**

Run the canonical build + install + launch chain.

Expected: build succeeds. The game over alert only appears at end-of-game; no immediate visible change at app launch. End-of-game text is verified manually in Task 10.

- [ ] **Step 3: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add ios/CHING/CHING/GameView.swift && \
  git commit -m "ios: 3-way game over alert with ranked scores"
```

---

## Task 10: Manual simulator playthrough + screenshot proof

**Files:**
- Create: `docs/superpowers/2026-06-06-phase-3-screenshot.png`

Manual verification of every Phase 3 bullet, captured by a single mid-game screenshot showing a paced AI turn in progress.

- [ ] **Step 1: Full test suite + engine suite green**

```bash
cd /Users/bramvanoost/Code/game-ching && xcodebuild test \
  -project ios/CHING/CHING.xcodeproj \
  -scheme CHING \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:CHINGTests 2>&1 | grep -E "Executed|TEST" | tail -5

cd /Users/bramvanoost/Code/game-ching/ios/CHINGEngine && swift test 2>&1 | grep "Executed" | tail -2
```

Expected:
- `GameStoreTests`: ~11 tests, all pass.
- Engine: `Executed 32 tests, with 0 failures`.

- [ ] **Step 2: Play a full game in the simulator**

Launch the app (canonical install + launch chain). Tap through:
- Difficulty picker visible at top, defaults to `Normal`.
- Roll → Pick a face → Bank when a coin is set aside.
- Footer reads `"JONES is thinking…"` for ~600ms.
- Then `"BOT 03 is thinking…"` for ~600ms.
- Then footer disappears, control back to YOU.
- Continue until the center tile row empties.
- Game over alert appears with a ranked summary.
- Tap `New Game`, board resets, picker remains at its previous selection.

- [ ] **Step 3: Capture a paced mid-game screenshot**

Mid-game, while the thinking footer is visible naming an AI (timing: take the screenshot during one of the ~600ms windows), run:

```bash
xcrun simctl io booted screenshot /Users/bramvanoost/Code/game-ching/docs/superpowers/2026-06-06-phase-3-screenshot.png
```

Inspect the PNG. Confirm it shows: the difficulty picker at top, the three-row vault (some tiles in some vaults if at least one bank happened), the thinking footer at the bottom.

- [ ] **Step 4: Commit the screenshot**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git add docs/superpowers/2026-06-06-phase-3-screenshot.png && \
  git commit -m "ios: phase 3 game feel, proof-of-life screenshot"
```

- [ ] **Step 5: Push and open PR**

```bash
cd /Users/bramvanoost/Code/game-ching && \
  git push -u origin phase-3-game-feel && \
  gh pr create --title "Phase 3: game feel (paced AI, 1v2, difficulty)" --body "$(cat <<'EOF'
## Summary

- Async `runAIIfNeeded(reduceMotion:)` with a 300ms `Task.sleep` between AI actions
- Cast grows from 1v1 to 1v2: YOU + JONES + BOT 03
- App-local `Difficulty` enum with `easy/normal/hard` modifier (±0.15), persisted via UserDefaults
- Segmented `DifficultyPicker` at top of the Game screen, bound to `store.difficulty`
- iOS Reduce Motion environment hook collapses the per-action delay to 0
- 3-way ranked game over alert with `"<NAME> wins."` or `"Tie at the top."`
- 11 GameStoreTests (5 adjusted from Phase 2 + 6 new), all green
- Engine: 32/32 tests still green, no engine code touched

## Test plan

- [ ] Difficulty picker visible at top, defaults to Normal
- [ ] Tap Easy/Hard → next AI decision reflects modified discipline
- [ ] Quit and relaunch → difficulty selection persists
- [ ] Play a turn → footer reads `"JONES is thinking…"` then `"BOT 03 is thinking…"` with ~300ms per AI action
- [ ] Settings > Accessibility > Reduce Motion ON → AI plays instantly, footer flashes
- [ ] Play to completion → game over alert ranks all three, names top scorer or `"Tie at the top."`
- [ ] Tap New Game → board resets, picker retains selection

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** Every "In Phase 3" bullet maps to a task. AI pacing + footer: Tasks 4, 7. 1v2 cast: Task 3. Difficulty picker + persistence: Tasks 1, 2, 6. Reduce Motion: Tasks 4, 8. Game over alert: Task 9. Tests: Tasks 1, 2, 3, 4, 5. Manual verification + screenshot: Task 10.
- **Spec deferrals respected:** No visual system, no other screens, no opponent selection, no sound/haptics, no resume-game persistence, no Merit, no color dots, no play log.
- **Type consistency:** `Difficulty` (app enum) appears in Tasks 1, 2, 3, 6. `CHINGEngine.Difficulty` (fully qualified) appears in Tasks 3 (`currentAIDifficulty`) and 5 (3-player termination test). Method `runAIIfNeeded(reduceMotion:)` consistent in Tasks 4, 5, 7, 8. Property `difficulty` consistent in Tasks 2, 3, 6. Constant `aiPaceNanoseconds = 300_000_000` defined in Task 4.
- **Placeholders:** none. Every code step has full code. Every command has expected output described.
- **CLAUDE.md global rule:** No em-dashes in plan body or code.

---

## Execution handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-06-phase-3-game-feel.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration. Best for catching surprises in the multi-edit tasks (Tasks 3, 4).

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints. Lower overhead.

**Which approach?**
