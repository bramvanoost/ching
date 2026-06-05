# CHING for iOS, Phase 1: Engine + AI Port + Parity Testing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the existing TypeScript CHING engine and AI to a pure Swift Package, prove byte-for-byte parity with the TS implementation through automated tests, and reproduce the 200-game AI-vs-AI regression in Swift.

**Architecture:** A standalone Swift Package at `/ios/CHINGEngine/` with no UI or platform dependencies. Pure structs and pure functions, randomness via an injected RNG protocol. A separate executable target inside the same package implements a CLI tool that the cross-engine parity harness drives. Tests live in `swift test` and run in CI alongside a Node script that runs the original TS engine on the same fixtures, with a diff script asserting state-trace equality.

**Tech Stack:** Swift 5.9+, Swift Package Manager, Swift Testing (the new framework, not XCTest), Node 22 + tsx for the TS-side parity runner, GitHub Actions for CI. No third-party Swift dependencies.

**Source of truth during port:** `src/engine.ts` and `src/ai.ts`. If the spec disagrees with the TS engine on rules, the TS engine wins (the parity harness enforces this).

---

## File structure (created in this phase)

- `ios/CHINGEngine/Package.swift` — package manifest, library + executable targets, test target.
- `ios/CHINGEngine/Sources/CHINGEngine/Types.swift` — `Face`, `Phase`, `Player`, `State`, `Action`, all `Codable`, all `Sendable`.
- `ios/CHINGEngine/Sources/CHINGEngine/Rng.swift` — `CHINGRandom` protocol plus `Mulberry32` deterministic RNG (bit-identical port of the TS one used in `sim/regression.ts`).
- `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift` — `step(state:action:rng:)` reducer plus `initialState`, `score`, `tileCoins`, `faceValue` helpers.
- `ios/CHINGEngine/Sources/CHINGEngine/AI.swift` — `Difficulty` struct, `decide(state:ai:)`.
- `ios/CHINGEngine/Sources/CHINGParityCLI/main.swift` — reads a parity case from stdin, drives the engine, writes a JSON trace to stdout.
- `ios/CHINGEngine/Tests/CHINGEngineTests/*.swift` — one file per concern (types, rng, engine roll/pick/stop/bust/end, ai, sim, integration).
- `parity/cases.json` — shared parity test cases.
- `parity/run-ts.mjs` — Node runner of the TS engine.
- `parity/diff.mjs` — runs both engines on all cases, asserts trace equality.
- `parity/README.md` — how the parity harness works and how to add cases.
- `.github/workflows/engine-ci.yml` — CI workflow for engine tests + parity tests + sim regression.

---

## Task 1: Swift Package skeleton

**Files:**
- Create: `ios/CHINGEngine/Package.swift`
- Create: `ios/CHINGEngine/Sources/CHINGEngine/.gitkeep`
- Create: `ios/CHINGEngine/Sources/CHINGParityCLI/.gitkeep`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/.gitkeep`

- [ ] **Step 1: Create the package directory tree**

```bash
mkdir -p ios/CHINGEngine/Sources/CHINGEngine
mkdir -p ios/CHINGEngine/Sources/CHINGParityCLI
mkdir -p ios/CHINGEngine/Tests/CHINGEngineTests
touch ios/CHINGEngine/Sources/CHINGEngine/.gitkeep
touch ios/CHINGEngine/Sources/CHINGParityCLI/.gitkeep
touch ios/CHINGEngine/Tests/CHINGEngineTests/.gitkeep
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CHINGEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CHINGEngine", targets: ["CHINGEngine"]),
        .executable(name: "ching-parity", targets: ["CHINGParityCLI"]),
    ],
    targets: [
        .target(name: "CHINGEngine"),
        .executableTarget(
            name: "CHINGParityCLI",
            dependencies: ["CHINGEngine"]
        ),
        .testTarget(
            name: "CHINGEngineTests",
            dependencies: ["CHINGEngine"]
        ),
    ]
)
```

- [ ] **Step 3: Verify the package builds**

Run from repo root:
```bash
cd ios/CHINGEngine && swift build
```
Expected: `Build complete!` with no warnings. (Empty targets compile fine.)

- [ ] **Step 4: Commit**

```bash
cd /Users/bramvanoost/Code/game-ching
git add ios/
git commit -m "ios: scaffold CHINGEngine swift package"
```

---

## Task 2: Type definitions

Port the TS types from `src/engine.ts` (lines 4-29) to Swift structs with `Codable` + `Sendable` conformance.

**Files:**
- Create: `ios/CHINGEngine/Sources/CHINGEngine/Types.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/TypesTests.swift`
- Modify: delete `ios/CHINGEngine/Sources/CHINGEngine/.gitkeep` and `ios/CHINGEngine/Tests/CHINGEngineTests/.gitkeep` (now that we have real files).

- [ ] **Step 1: Write the failing test**

`ios/CHINGEngine/Tests/CHINGEngineTests/TypesTests.swift`:

```swift
import Testing
import Foundation
@testable import CHINGEngine

@Test
func roundTripStateCodable() throws {
    let original = State(
        players: [
            Player(id: "P0", tiles: [22, 28]),
            Player(id: "P1", tiles: [],),
        ],
        current: 0,
        centerTiles: [21, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 36],
        diceInHand: 5,
        rolled: [.three, .three, .five, .coin, .one],
        setAside: [.two, .two, .four],
        pickedFaces: [.two, .four],
        phase: .pick
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(State.self, from: data)
    #expect(decoded == original)
}

@Test
func faceValueOfCoinIsFive() {
    #expect(Face.coin.value == 5)
    #expect(Face.one.value == 1)
    #expect(Face.five.value == 5)
}

@Test
func tileCoinsTiers() {
    #expect(tileCoins(21) == 1)
    #expect(tileCoins(24) == 1)
    #expect(tileCoins(25) == 2)
    #expect(tileCoins(28) == 2)
    #expect(tileCoins(29) == 3)
    #expect(tileCoins(32) == 3)
    #expect(tileCoins(33) == 4)
    #expect(tileCoins(36) == 4)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ios/CHINGEngine && swift test
```
Expected: build failure (`State`, `Player`, `Face`, `Phase`, `tileCoins` not defined).

- [ ] **Step 3: Write the types**

`ios/CHINGEngine/Sources/CHINGEngine/Types.swift`:

```swift
import Foundation

public enum Face: Int, Codable, Sendable, CaseIterable, Equatable {
    case one = 1, two = 2, three = 3, four = 4, five = 5, coin = 6

    public var value: Int {
        self == .coin ? 5 : rawValue
    }
}

public enum Phase: String, Codable, Sendable, Equatable {
    case roll, pick, over
}

public struct Player: Codable, Sendable, Equatable {
    public var id: String
    public var tiles: [Int]

    public init(id: String, tiles: [Int]) {
        self.id = id
        self.tiles = tiles
    }
}

public struct State: Codable, Sendable, Equatable {
    public var players: [Player]
    public var current: Int
    public var centerTiles: [Int]
    public var diceInHand: Int
    public var rolled: [Face]
    public var setAside: [Face]
    public var pickedFaces: [Face]
    public var phase: Phase

    public init(
        players: [Player],
        current: Int,
        centerTiles: [Int],
        diceInHand: Int,
        rolled: [Face],
        setAside: [Face],
        pickedFaces: [Face],
        phase: Phase
    ) {
        self.players = players
        self.current = current
        self.centerTiles = centerTiles
        self.diceInHand = diceInHand
        self.rolled = rolled
        self.setAside = setAside
        self.pickedFaces = pickedFaces
        self.phase = phase
    }
}

public enum Action: Codable, Sendable, Equatable {
    case roll
    case pick(face: Face)
    case stop
}

public let TOTAL_DICE = 8

public func tileCoins(_ tile: Int) -> Int {
    if tile <= 24 { return 1 }
    if tile <= 28 { return 2 }
    if tile <= 32 { return 3 }
    return 4
}
```

Also delete the gitkeeps:
```bash
rm ios/CHINGEngine/Sources/CHINGEngine/.gitkeep
rm ios/CHINGEngine/Tests/CHINGEngineTests/.gitkeep
```

- [ ] **Step 4: Run tests, expect green**

```bash
cd ios/CHINGEngine && swift test
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: port core types from ts engine"
```

---

## Task 3: Deterministic RNG (mulberry32)

Port the TS `mulberry32` from `sim/regression.ts:7-16`. The Swift port must produce byte-identical outputs for the same seed; this is the foundation of all parity testing.

**Files:**
- Create: `ios/CHINGEngine/Sources/CHINGEngine/Rng.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/RngTests.swift`

- [ ] **Step 1: Capture expected values from the TS RNG**

Run from repo root:
```bash
cd /Users/bramvanoost/Code/game-ching
npx tsx -e '
import { } from "./src/engine.js";
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const r = mulberry32(1);
const xs = [];
for (let i = 0; i < 10; i++) xs.push(r());
console.log(JSON.stringify(xs));
'
```

Record the 10 doubles printed; you will paste them into the Swift test verbatim. Example shape (your actual numbers will be the same since this is deterministic):
`[0.6270739405881613, 0.0017637100536376238, ...]`

- [ ] **Step 2: Write the failing test**

`ios/CHINGEngine/Tests/CHINGEngineTests/RngTests.swift`. **Replace the array below with the values you captured in Step 1**:

```swift
import Testing
@testable import CHINGEngine

@Test
func mulberry32MatchesTsForSeed1() {
    var rng = Mulberry32(seed: 1)
    let expected: [Double] = [
        // PASTE 10 VALUES FROM STEP 1 HERE
    ]
    for value in expected {
        let actual = rng.next()
        #expect(actual == value, "mulberry32 drift at seed=1")
    }
}

@Test
func mulberry32SequenceIsRepeatable() {
    var a = Mulberry32(seed: 42)
    var b = Mulberry32(seed: 42)
    for _ in 0..<100 {
        #expect(a.next() == b.next())
    }
}
```

- [ ] **Step 3: Run test, expect compile error**

```bash
cd ios/CHINGEngine && swift test
```
Expected: `Mulberry32` not defined.

- [ ] **Step 4: Implement the RNG**

`ios/CHINGEngine/Sources/CHINGEngine/Rng.swift`:

```swift
import Foundation

/// A deterministic pseudo-random source returning Doubles in [0, 1).
/// Matches the contract of TS `Rng` from src/engine.ts.
public protocol CHINGRandom {
    mutating func next() -> Double
}

/// Bit-identical port of the mulberry32 PRNG used in sim/regression.ts.
/// Must produce the same sequence as the TS implementation for the same seed,
/// since parity tests rely on this.
public struct Mulberry32: CHINGRandom {
    private var a: UInt32

    public init(seed: UInt32) {
        self.a = seed
    }

    public mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t: UInt32 = a
        t = (t ^ (t &>> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t &>> 7)) &* (t | 61)))
        let result: UInt32 = t ^ (t &>> 14)
        return Double(result) / 4_294_967_296.0
    }
}
```

Notes:
- `&+` and `&*` are wrapping arithmetic, matching JS `Math.imul` and `>>> 0` truncation semantics.
- `&>>` is the masking shift; on `UInt32` it behaves as the unsigned right shift `>>>` in JS.

- [ ] **Step 5: Run tests, expect green**

```bash
cd ios/CHINGEngine && swift test
```
Expected: 2 RNG tests + 3 type tests = 5 tests pass. If the RNG test fails, you have wrapping or sign drift; re-check `&+` vs `+`, and that all intermediates are `UInt32`.

- [ ] **Step 6: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: port mulberry32 rng, bit-identical to ts"
```

---

## Task 4: initialState + score helpers

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/Types.swift` (add `score` helper next to `tileCoins`)
- Create: `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/EngineInitTests.swift`

- [ ] **Step 1: Write failing tests**

`ios/CHINGEngine/Tests/CHINGEngineTests/EngineInitTests.swift`:

```swift
import Testing
@testable import CHINGEngine

@Test
func initialStateForTwoPlayers() {
    let s = initialState(playerIds: ["P0", "P1"])
    #expect(s.players.count == 2)
    #expect(s.players[0].id == "P0")
    #expect(s.players[1].tiles.isEmpty)
    #expect(s.current == 0)
    #expect(s.centerTiles == Array(21...36))
    #expect(s.diceInHand == 8)
    #expect(s.rolled.isEmpty)
    #expect(s.setAside.isEmpty)
    #expect(s.pickedFaces.isEmpty)
    #expect(s.phase == .roll)
}

@Test
func scoreSumsTileCoinsPerPlayer() {
    let s = State(
        players: [
            Player(id: "P0", tiles: [22, 28, 33]),  // 1 + 2 + 4 = 7
            Player(id: "P1", tiles: [25, 36]),       // 2 + 4 = 6
        ],
        current: 0, centerTiles: [], diceInHand: 8,
        rolled: [], setAside: [], pickedFaces: [], phase: .roll
    )
    #expect(score(s) == [7, 6])
}
```

- [ ] **Step 2: Run tests, expect failure**

```bash
cd ios/CHINGEngine && swift test
```
Expected: `initialState`, `score` not defined.

- [ ] **Step 3: Implement**

`ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`:

```swift
import Foundation

public func initialState(playerIds: [String]) -> State {
    State(
        players: playerIds.map { Player(id: $0, tiles: []) },
        current: 0,
        centerTiles: Array(21...36),
        diceInHand: TOTAL_DICE,
        rolled: [],
        setAside: [],
        pickedFaces: [],
        phase: .roll
    )
}

public func score(_ state: State) -> [Int] {
    state.players.map { $0.tiles.reduce(0) { $0 + tileCoins($1) } }
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: initial state + score helpers"
```

---

## Task 5: ROLL action — happy path

Port `doRoll` from `src/engine.ts:80-89` excluding the bust branch (covered in Task 6).

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/EngineRollTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import CHINGEngine

@Test
func rollProducesEightDiceFromFreshState() {
    var rng = Mulberry32(seed: 1)
    let s0 = initialState(playerIds: ["P0", "P1"])
    let s1 = step(state: s0, action: .roll, rng: &rng)
    #expect(s1.rolled.count == 8)
    #expect(s1.phase == .pick)
    #expect(s1.diceInHand == 8)  // not consumed until PICK
}

@Test
func rollNoopWhenPhaseIsNotRoll() {
    var rng = Mulberry32(seed: 1)
    var s = initialState(playerIds: ["P0", "P1"])
    s.phase = .pick
    let s2 = step(state: s, action: .roll, rng: &rng)
    #expect(s2 == s)
}

@Test
func rollNoopWhenDiceInHandIsZero() {
    var rng = Mulberry32(seed: 1)
    var s = initialState(playerIds: ["P0", "P1"])
    s.diceInHand = 0
    let s2 = step(state: s, action: .roll, rng: &rng)
    #expect(s2 == s)
}
```

- [ ] **Step 2: Run tests, expect failure**

```bash
cd ios/CHINGEngine && swift test
```
Expected: `step` not defined.

- [ ] **Step 3: Implement `step` (dispatch) and ROLL (happy path only)**

Append to `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`:

```swift
public func step<R: CHINGRandom>(state: State, action: Action, rng: inout R) -> State {
    if state.phase == .over { return state }
    switch action {
    case .roll:
        return applyRoll(state, rng: &rng)
    case .pick:
        return state  // implemented in Task 7
    case .stop:
        return state  // implemented in Task 9
    }
}

func rollDie<R: CHINGRandom>(rng: inout R) -> Face {
    let n = Int(rng.next() * 6) + 1
    let clamped = max(1, min(6, n))
    return Face(rawValue: clamped)!
}

func applyRoll<R: CHINGRandom>(_ state: State, rng: inout R) -> State {
    guard state.phase == .roll, state.diceInHand > 0 else { return state }
    let rolled = (0..<state.diceInHand).map { _ in rollDie(rng: &rng) }
    // Bust-on-no-new-face branch is added in Task 6.
    var next = state
    next.rolled = rolled
    next.phase = .pick
    return next
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: roll action happy path"
```

---

## Task 6: ROLL action — bust when no new face appears

Port the bust branch from `src/engine.ts:84-87`. If every rolled die is a face the player has already picked, the player has nothing legal to pick: this is a bust.

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`
- Modify: `ios/CHINGEngine/Tests/CHINGEngineTests/EngineRollTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `EngineRollTests.swift`:

```swift
@Test
func rollBustsWhenAllFacesAlreadyPicked() {
    // Setup: player has picked faces 1 and 2. Only one die left, RNG forces it to 1.
    // Player must bust because no new face is available.
    struct ForcedOne: CHINGRandom {
        mutating func next() -> Double { 0.0 }  // -> floor(0 * 6) + 1 = 1
    }
    var rng = ForcedOne()
    var s = initialState(playerIds: ["P0", "P1"])
    s.pickedFaces = [.one, .two]
    s.diceInHand = 1
    s.players[0].tiles = [28]
    let after = step(state: s, action: .roll, rng: &rng)
    // Bust: top tile returned to center (sorted), highest center burned, turn ends.
    #expect(after.players[0].tiles == [])
    #expect(after.centerTiles.last == 35)  // 36 burned, 28 returned
    #expect(after.centerTiles.contains(28))
    #expect(after.current == 1)
    #expect(after.phase == .roll)
}
```

- [ ] **Step 2: Run test, expect failure**

```bash
cd ios/CHINGEngine && swift test
```

The roll succeeds and the test fails on the bust assertions.

- [ ] **Step 3: Implement the bust branch in ROLL and the bust helper + endTurn**

Append to `Engine.swift`:

```swift
func endTurn(_ state: State) -> State {
    if state.centerTiles.isEmpty {
        var s = state
        s.phase = .over
        s.rolled = []
        s.setAside = []
        s.pickedFaces = []
        s.diceInHand = 0
        return s
    }
    var s = state
    s.current = (state.current + 1) % state.players.count
    s.diceInHand = TOTAL_DICE
    s.rolled = []
    s.setAside = []
    s.pickedFaces = []
    s.phase = .roll
    return s
}

func bust(_ state: State) -> State {
    var players = state.players
    var centerTiles = state.centerTiles
    let me = players[state.current]
    if let top = me.tiles.last {
        players[state.current].tiles.removeLast()
        centerTiles.append(top)
        centerTiles.sort()
    }
    // Burn the highest remaining center tile so the supply depletes (CLAUDE.md).
    if !centerTiles.isEmpty {
        centerTiles.removeLast()
    }
    var s = state
    s.players = players
    s.centerTiles = centerTiles
    return endTurn(s)
}
```

Replace `applyRoll`:

```swift
func applyRoll<R: CHINGRandom>(_ state: State, rng: inout R) -> State {
    guard state.phase == .roll, state.diceInHand > 0 else { return state }
    let rolled = (0..<state.diceInHand).map { _ in rollDie(rng: &rng) }
    let hasNewFace = rolled.contains { !state.pickedFaces.contains($0) }
    if !hasNewFace {
        return bust(state)
    }
    var next = state
    next.rolled = rolled
    next.phase = .pick
    return next
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: roll bust + endTurn + bust cleanup"
```

---

## Task 7: PICK action

Port `doPick` from `src/engine.ts:91-109`. Includes the auto-bank-when-all-dice-used branch.

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/EnginePickTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import CHINGEngine

private func freshState() -> State {
    initialState(playerIds: ["P0", "P1"])
}

@Test
func pickLocksAllDiceOfFace() {
    var s = freshState()
    s.phase = .pick
    s.rolled = [.three, .three, .four, .five, .coin, .one, .two, .three]
    let s2 = step(state: s, action: .pick(face: .three), rng: &dummyRng())
    #expect(s2.setAside == [.three, .three, .three])
    #expect(s2.pickedFaces == [.three])
    #expect(s2.diceInHand == 5)
    #expect(s2.rolled == [])
    #expect(s2.phase == .roll)
}

@Test
func pickNoopWhenFaceAlreadyPicked() {
    var s = freshState()
    s.phase = .pick
    s.rolled = [.three, .four]
    s.pickedFaces = [.three]
    let s2 = step(state: s, action: .pick(face: .three), rng: &dummyRng())
    #expect(s2 == s)
}

@Test
func pickNoopWhenFaceNotInRolled() {
    var s = freshState()
    s.phase = .pick
    s.rolled = [.three, .four]
    let s2 = step(state: s, action: .pick(face: .five), rng: &dummyRng())
    #expect(s2 == s)
}

@Test
func pickConsumingLastDieAutoBanks() {
    // 8 dice all coin face, pick coin -> diceInHand = 0 -> tryBank.
    // sum = 8 * 5 = 40, contains coin, take highest tile <= 40 = 36.
    var s = freshState()
    s.phase = .pick
    s.rolled = Array(repeating: .coin, count: 8)
    let s2 = step(state: s, action: .pick(face: .coin), rng: &dummyRng())
    #expect(s2.players[0].tiles == [36])
    #expect(s2.centerTiles.last == 35)
    #expect(s2.current == 1)
}

// Helper for tests that should not consume randomness.
private func dummyRng() -> Mulberry32 {
    Mulberry32(seed: 0)
}
```

Note: the helper `dummyRng()` returns a value, but we need an `inout` to pass; Swift requires this be assigned to a variable. The Swift Testing framework runs each `@Test` as a function, so wrap as needed. Adjust as:

```swift
@Test
func pickLocksAllDiceOfFace() {
    var s = freshState()
    s.phase = .pick
    s.rolled = [.three, .three, .four, .five, .coin, .one, .two, .three]
    var rng = Mulberry32(seed: 0)
    let s2 = step(state: s, action: .pick(face: .three), rng: &rng)
    // ... assertions same
}
```

Apply the `var rng = Mulberry32(seed: 0)` pattern inline in each test instead of the helper, then remove the helper.

- [ ] **Step 2: Run tests, expect failure**

```bash
cd ios/CHINGEngine && swift test
```
Expected: PICK currently returns state unchanged, so tests fail.

- [ ] **Step 3: Implement PICK + `tryBank` skeleton (center-only)**

Inside `Engine.swift`, replace the `.pick` case in `step`:

```swift
case .pick(let face):
    return applyPick(state, face: face)
```

Add functions:

```swift
func applyPick(_ state: State, face: Face) -> State {
    guard state.phase == .pick else { return state }
    guard !state.pickedFaces.contains(face) else { return state }
    let taken = state.rolled.filter { $0 == face }
    guard !taken.isEmpty else { return state }
    var next = state
    next.setAside.append(contentsOf: taken)
    next.pickedFaces.append(face)
    next.diceInHand -= taken.count
    next.rolled = []
    next.phase = .roll
    if next.diceInHand == 0 {
        return tryBank(next)
    }
    return next
}

func tryBank(_ state: State) -> State {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    let hasCoin = state.setAside.contains(.coin)
    guard hasCoin else { return bust(state) }

    // Center: take the highest tile <= sum.
    let available = state.centerTiles.filter { $0 <= sum }
    guard !available.isEmpty else { return bust(state) }
    let taken = available.max()!
    var next = state
    next.centerTiles.removeAll { $0 == taken }
    next.players[state.current].tiles.append(taken)
    return endTurn(next)
}
```

(Steal-from-rival branch is added in Task 9.)

- [ ] **Step 4: Run tests, expect green**

Expected: 15 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: pick action + tryBank center branch"
```

---

## Task 8: STOP action

Port `doStop` from `src/engine.ts:111-115`. Reuses `tryBank` from Task 7.

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/EngineStopTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import CHINGEngine

@Test
func stopBanksWhenInRollPhaseWithSetAside() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    s.phase = .roll
    s.setAside = [.coin, .four, .three]  // sum = 12... too low for a tile
    // Sum 12 < any center tile (smallest is 21), so this should bust.
    let s2 = step(state: s, action: .stop, rng: &rng)
    #expect(s2.players[0].tiles == [])
    #expect(s2.current == 1)
}

@Test
func stopNoopWhenSetAsideEmpty() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    // phase already .roll, setAside empty
    let s2 = step(state: s, action: .stop, rng: &rng)
    #expect(s2 == s)
}

@Test
func stopBanksHighestAvailableTile() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    s.phase = .roll
    s.setAside = [.coin, .coin, .five, .four, .four]  // 5+5+5+4+4 = 23
    let s2 = step(state: s, action: .stop, rng: &rng)
    #expect(s2.players[0].tiles == [23])
    #expect(!s2.centerTiles.contains(23))
    #expect(s2.current == 1)
}
```

- [ ] **Step 2: Run tests, expect failure**

```bash
cd ios/CHINGEngine && swift test
```

- [ ] **Step 3: Implement STOP**

Replace the `.stop` case in `step`:

```swift
case .stop:
    return applyStop(state)
```

Add:

```swift
func applyStop(_ state: State) -> State {
    guard state.phase == .roll else { return state }
    guard !state.setAside.isEmpty else { return state }
    return tryBank(state)
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 18 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: stop action"
```

---

## Task 9: Steal branch in `tryBank`

Port the steal-from-rival branch from `src/engine.ts:122-135`. Before taking from the center, check whether the sum exactly matches any rival's top tile; if so, steal it.

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/Engine.swift`
- Modify: `ios/CHINGEngine/Tests/CHINGEngineTests/EngineStopTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `EngineStopTests.swift`:

```swift
@Test
func stopStealsRivalTopTileOnExactMatch() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    s.players[1].tiles = [25]
    s.phase = .roll
    s.setAside = [.coin, .coin, .five, .five, .five]  // sum 25 (coin = 5)
    let s2 = step(state: s, action: .stop, rng: &rng)
    #expect(s2.players[0].tiles == [25])
    #expect(s2.players[1].tiles == [])
    // The 25 in center is untouched because steal occurred first.
    #expect(s2.centerTiles.contains(25))
}

@Test
func stopPrefersStealOverCenterWhenBothPossible() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    s.players[1].tiles = [24]
    s.phase = .roll
    s.setAside = [.coin, .coin, .five, .five, .four]  // sum 24
    let s2 = step(state: s, action: .stop, rng: &rng)
    #expect(s2.players[0].tiles == [24])
    #expect(s2.players[1].tiles == [])
    #expect(s2.centerTiles.contains(24))
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement steal in `tryBank`**

Replace `tryBank`:

```swift
func tryBank(_ state: State) -> State {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    let hasCoin = state.setAside.contains(.coin)
    guard hasCoin else { return bust(state) }

    // Steal: exact match on a rival's top tile takes priority over the center.
    for i in state.players.indices where i != state.current {
        if let rivalTop = state.players[i].tiles.last, rivalTop == sum {
            var next = state
            next.players[i].tiles.removeLast()
            next.players[state.current].tiles.append(sum)
            return endTurn(next)
        }
    }

    let available = state.centerTiles.filter { $0 <= sum }
    guard !available.isEmpty else { return bust(state) }
    let taken = available.max()!
    var next = state
    next.centerTiles.removeAll { $0 == taken }
    next.players[state.current].tiles.append(taken)
    return endTurn(next)
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 20 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: steal branch in tryBank"
```

---

## Task 10: Game end (center depleted)

The end-of-game phase transition is already implemented in `endTurn` (Task 6). Add explicit tests proving it works end-to-end.

**Files:**
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/EngineEndTests.swift`

- [ ] **Step 1: Write the test**

```swift
import Testing
@testable import CHINGEngine

@Test
func gameEndsWhenLastCenterTileIsBanked() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    s.centerTiles = [21]  // only one tile left
    s.phase = .roll
    s.setAside = [.coin, .coin, .five, .five, .one]  // sum 21
    let s2 = step(state: s, action: .stop, rng: &rng)
    #expect(s2.phase == .over)
    #expect(s2.players[0].tiles == [21])
    #expect(s2.centerTiles.isEmpty)
}

@Test
func stepIsNoOpWhenPhaseIsOver() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0"])
    s.phase = .over
    let s2 = step(state: s, action: .roll, rng: &rng)
    #expect(s2 == s)
}

@Test
func gameEndsAfterBustOfFinalTile() {
    var rng = Mulberry32(seed: 0)
    var s = initialState(playerIds: ["P0", "P1"])
    s.centerTiles = [21]  // only one tile
    s.players[0].tiles = []  // nothing to return
    s.phase = .roll
    s.setAside = [.three]  // no coin -> bust
    let s2 = step(state: s, action: .stop, rng: &rng)
    // bust burns the highest center tile (21), leaving none -> game ends.
    #expect(s2.phase == .over)
    #expect(s2.centerTiles.isEmpty)
}
```

- [ ] **Step 2: Run tests, expect green**

Expected: 23 tests pass. (No new implementation; this validates existing code.)

- [ ] **Step 3: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: tests for end-of-game phase"
```

---

## Task 11: AI — pickFace

Port `pickFace` from `src/ai.ts:26-35`. Strategy: if no coin yet picked and coin is available, take coin; otherwise take the face that maximizes `count * faceValue`.

**Files:**
- Create: `ios/CHINGEngine/Sources/CHINGEngine/AI.swift`
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/AITests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import CHINGEngine

@Test
func aiPicksCoinFirstWhenAvailable() {
    var s = initialState(playerIds: ["P0", "P1"])
    s.phase = .pick
    s.rolled = [.coin, .three, .three, .three, .three, .three, .three, .three]
    let action = decide(state: s, ai: Difficulty(discipline: 0.5))
    #expect(action == .pick(face: .coin))
}

@Test
func aiPicksHighestValueGroupWhenCoinAlreadyHeld() {
    var s = initialState(playerIds: ["P0", "P1"])
    s.phase = .pick
    s.setAside = [.coin]
    s.pickedFaces = [.coin]
    s.rolled = [.three, .three, .three, .four, .four]
    // 3 threes = 9, 2 fours = 8 -> pick threes
    let action = decide(state: s, ai: Difficulty(discipline: 0.5))
    #expect(action == .pick(face: .three))
}

@Test
func aiPicksAnythingPresentWhenNoCoinAvailable() {
    var s = initialState(playerIds: ["P0", "P1"])
    s.phase = .pick
    s.rolled = [.one, .one]
    let action = decide(state: s, ai: Difficulty(discipline: 0.5))
    #expect(action == .pick(face: .one))
}
```

- [ ] **Step 2: Run tests, expect failure**

```bash
cd ios/CHINGEngine && swift test
```

- [ ] **Step 3: Implement AI pick + skeleton `decide`**

`ios/CHINGEngine/Sources/CHINGEngine/AI.swift`:

```swift
import Foundation

public struct Difficulty: Sendable, Equatable {
    public var discipline: Double
    public init(discipline: Double) {
        self.discipline = discipline
    }
}

public func decide(state: State, ai: Difficulty) -> Action {
    if state.phase == .pick {
        return .pick(face: pickFace(state))
    }
    if state.setAside.isEmpty {
        return .roll
    }
    return continueOrStop(state, ai: ai)
}

func pickFace(_ state: State) -> Face {
    let candidates = Face.allCases.filter { face in
        !state.pickedFaces.contains(face) && state.rolled.contains(face)
    }
    let hasCoin = state.setAside.contains(.coin)
    if !hasCoin, candidates.contains(.coin) {
        return .coin
    }
    func valueOf(_ f: Face) -> Int {
        state.rolled.filter { $0 == f }.count * f.value
    }
    return candidates.reduce(candidates.first!) { best, f in
        valueOf(f) > valueOf(best) ? f : best
    }
}

func continueOrStop(_ state: State, ai: Difficulty) -> Action {
    // Always-ROLL placeholder; replaced in Task 12.
    return .roll
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 26 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "ai: pickFace strategy"
```

---

## Task 12: AI — continueOrStop

Port `continueOrStop` from `src/ai.ts:37-64`. Discipline drives both bust tolerance and desired tile tier.

**Files:**
- Modify: `ios/CHINGEngine/Sources/CHINGEngine/AI.swift`
- Modify: `ios/CHINGEngine/Tests/CHINGEngineTests/AITests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `AITests.swift`:

```swift
@Test
func aiRollsWhenNoCoinHeld() {
    var s = initialState(playerIds: ["P0", "P1"])
    s.setAside = [.three, .four]  // no coin
    let action = decide(state: s, ai: Difficulty(discipline: 1.0))
    #expect(action == .roll)
}

@Test
func cautiousAiStopsAtAnyReachableTile() {
    var s = initialState(playerIds: ["P0", "P1"])
    s.setAside = [.coin, .coin, .coin, .coin, .one]  // sum 21
    s.diceInHand = 3
    s.pickedFaces = [.coin, .one]
    let action = decide(state: s, ai: Difficulty(discipline: 1.0))
    #expect(action == .stop)
}

@Test
func greedyAiKeepsRollingForHigherTier() {
    var s = initialState(playerIds: ["P0", "P1"])
    s.setAside = [.coin, .coin, .coin, .coin, .one]  // sum 21 -> tier 1
    s.diceInHand = 3
    s.pickedFaces = [.coin, .one]
    let action = decide(state: s, ai: Difficulty(discipline: 0.0))
    #expect(action == .roll)
}

@Test
func aiStopsWhenBustRiskExceedsCeiling() {
    var s = initialState(playerIds: ["P0", "P1"])
    // Five faces picked, only 1 die left -> bust prob = (5/6)^1 ~= 0.833
    // bustCeiling at discipline 0.5 = 0.75 - 0.3 = 0.45 < 0.833 -> STOP
    s.setAside = [.coin, .one, .two, .three, .four]
    s.pickedFaces = [.coin, .one, .two, .three, .four]
    s.diceInHand = 1
    // sum = 5+1+2+3+4 = 15, no center tile reachable -> bestBankableTile = nil -> ROLL
    // To exercise the bustCeiling path, force a reachable tile.
    s.setAside = [.coin, .coin, .coin, .coin, .one]  // sum 21
    s.pickedFaces = [.coin, .one, .two, .three, .four]
    s.diceInHand = 1
    let action = decide(state: s, ai: Difficulty(discipline: 0.5))
    #expect(action == .stop)
}
```

- [ ] **Step 2: Run tests, expect failure**

- [ ] **Step 3: Implement `continueOrStop` and `bestBankableTile`**

Replace the placeholder `continueOrStop` and add `bestBankableTile`:

```swift
func continueOrStop(_ state: State, ai: Difficulty) -> Action {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    let hasCoin = state.setAside.contains(.coin)
    guard hasCoin else { return .roll }

    guard let target = bestBankableTile(state, sum: sum) else { return .roll }

    let pickedCount = state.pickedFaces.count
    let bustProb = pow(Double(pickedCount) / 6.0, Double(state.diceInHand))

    // Bust tolerance shrinks sharply as discipline rises.
    // Greedy (0.0) tolerates up to 0.75, cautious (1.0) bails at 0.15.
    let bustCeiling = 0.75 - ai.discipline * 0.6
    if bustProb >= bustCeiling { return .stop }

    // Cap target tier by what's still reachable so we don't wait for tiles
    // that no longer exist.
    let ceiling: Int = state.centerTiles.isEmpty
        ? 4
        : tileCoins(state.centerTiles.last!)
    // Discipline narrows ambition: 0 holds out for 4-coin tiles, 1 banks any.
    let desiredTier = max(1, min(ceiling, Int((4.0 - ai.discipline * 3.5).rounded())))
    if tileCoins(target) >= desiredTier { return .stop }

    return .roll
}

func bestBankableTile(_ state: State, sum: Int) -> Int? {
    for i in state.players.indices where i != state.current {
        if let top = state.players[i].tiles.last, top == sum {
            return sum
        }
    }
    let available = state.centerTiles.filter { $0 <= sum }
    return available.max()
}
```

- [ ] **Step 4: Run tests, expect green**

Expected: 30 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "ai: continueOrStop with discipline-driven bust + tier logic"
```

---

## Task 13: Integration — play a full game

Add an end-to-end test that plays AI vs AI from `initialState` until `.over`, asserting the game terminates within a step budget.

**Files:**
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/IntegrationTests.swift`

- [ ] **Step 1: Write the test**

```swift
import Testing
@testable import CHINGEngine

@Test
func aiVsAiGameTerminates() {
    var rng = Mulberry32(seed: 1)
    var state = initialState(playerIds: ["P0", "P1"])
    let lowDisc = Difficulty(discipline: 0.2)
    let highDisc = Difficulty(discipline: 0.8)
    var steps = 0
    let MAX_STEPS = 5000
    while state.phase != .over {
        steps += 1
        #expect(steps < MAX_STEPS, "game did not terminate in \(MAX_STEPS) steps")
        if steps >= MAX_STEPS { break }
        let ai = state.current == 0 ? lowDisc : highDisc
        let action = decide(state: state, ai: ai)
        state = step(state: state, action: action, rng: &rng)
    }
    #expect(state.phase == .over)
    #expect(state.centerTiles.isEmpty)
}
```

- [ ] **Step 2: Run, expect green**

Expected: 31 tests pass. If termination fails, the bust-burn rule (Task 6) is the most likely culprit.

- [ ] **Step 3: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "engine: end-to-end termination test"
```

---

## Task 14: 200-game sim regression

Port `sim/regression.ts:18-66` to Swift. Run as part of `swift test`; assert that higher discipline wins more than lower discipline over 200 games.

**Files:**
- Create: `ios/CHINGEngine/Tests/CHINGEngineTests/SimRegressionTest.swift`

- [ ] **Step 1: Write the test**

```swift
import Testing
@testable import CHINGEngine

@Test
func higherDisciplineBeatsLowerOver200Games() {
    let GAMES = 200
    let DISC_LOW = 0.2
    let DISC_HIGH = 0.8
    let MAX_STEPS = 50_000

    var lowWins = 0
    var highWins = 0
    var ties = 0

    for g in 0..<GAMES {
        var rng = Mulberry32(seed: UInt32(g + 1))
        // Alternate seats so first-mover advantage doesn't skew the result.
        let playerDisc: [Double] = g % 2 == 0 ? [DISC_LOW, DISC_HIGH] : [DISC_HIGH, DISC_LOW]
        var state = initialState(playerIds: ["P0", "P1"])
        var steps = 0
        while state.phase != .over {
            steps += 1
            #expect(steps < MAX_STEPS, "game \(g) did not terminate")
            if steps >= MAX_STEPS { break }
            let ai = Difficulty(discipline: playerDisc[state.current])
            state = step(state: state, action: decide(state: state, ai: ai), rng: &rng)
        }
        let scores = score(state)
        let lowScore = playerDisc[0] == DISC_LOW ? scores[0] : scores[1]
        let highScore = playerDisc[0] == DISC_LOW ? scores[1] : scores[0]
        if highScore > lowScore { highWins += 1 }
        else if lowScore > highScore { lowWins += 1 }
        else { ties += 1 }
    }

    #expect(highWins > lowWins, "higher discipline (\(highWins)) did not beat lower (\(lowWins))")
}
```

- [ ] **Step 2: Run, expect green**

```bash
cd ios/CHINGEngine && swift test
```
Expected: 32 tests pass. This is the same regression the TS sim runs; the Swift port must reproduce the result. If it fails, you have a port bug somewhere upstream, not a flake. Check parity tests in Tasks 16-18 to localize.

- [ ] **Step 3: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "sim: 200-game regression in swift"
```

---

## Task 15: Parity CLI — Swift side

Build the `ching-parity` executable defined in `Package.swift`. It reads one parity case from stdin (a JSON object) and writes a JSON trace to stdout.

**Files:**
- Create: `ios/CHINGEngine/Sources/CHINGParityCLI/main.swift`

Schema of a parity case:
```json
{
  "seed": 1,
  "playerIds": ["P0", "P1"],
  "actions": [
    {"type": "ROLL"},
    {"type": "PICK", "face": 6},
    {"type": "STOP"}
  ]
}
```

Schema of trace output (one State per applied action, plus initial):
```json
{
  "states": [
    {"current": 0, "phase": "roll", "centerTilesLen": 16, "diceInHand": 8, ...},
    ...
  ]
}
```

- [ ] **Step 1: Write the CLI**

`ios/CHINGEngine/Sources/CHINGParityCLI/main.swift`:

```swift
import Foundation
import CHINGEngine

struct ParityCase: Codable {
    struct ActionDTO: Codable {
        let type: String
        let face: Int?
    }
    let seed: UInt32
    let playerIds: [String]
    let actions: [ActionDTO]
}

struct ParityTrace: Codable {
    let states: [State]
}

func actionFrom(_ dto: ParityCase.ActionDTO) -> Action {
    switch dto.type {
    case "ROLL": return .roll
    case "STOP": return .stop
    case "PICK":
        guard let raw = dto.face, let face = Face(rawValue: raw) else {
            fatalError("invalid PICK face")
        }
        return .pick(face: face)
    default:
        fatalError("unknown action type \(dto.type)")
    }
}

let input = FileHandle.standardInput.availableData
let testCase = try JSONDecoder().decode(ParityCase.self, from: input)

var rng = Mulberry32(seed: testCase.seed)
var state = initialState(playerIds: testCase.playerIds)
var trace: [State] = [state]
for dto in testCase.actions {
    state = step(state: state, action: actionFrom(dto), rng: &rng)
    trace.append(state)
}

let out = try JSONEncoder().encode(ParityTrace(states: trace))
FileHandle.standardOutput.write(out)
```

- [ ] **Step 2: Verify it builds**

```bash
cd ios/CHINGEngine && swift build --product ching-parity
```
Expected: build success, executable at `.build/debug/ching-parity`.

- [ ] **Step 3: Smoke-test by piping a simple case**

```bash
echo '{"seed":1,"playerIds":["P0","P1"],"actions":[{"type":"ROLL"}]}' \
  | ./.build/debug/ching-parity \
  | python3 -m json.tool | head -30
```
Expected: a JSON object with a `states` array of length 2 (initial + post-roll).

- [ ] **Step 4: Commit**

```bash
git add ios/CHINGEngine/
git commit -m "parity: swift cli reads case, writes trace"
```

---

## Task 16: Parity Node runner + cases.json

Mirror the Swift CLI on the TypeScript side: a Node script that reads the same `ParityCase` JSON, drives the TS engine, and emits an equivalent trace.

**Files:**
- Create: `parity/cases.json`
- Create: `parity/run-ts.mjs`
- Create: `parity/README.md`

- [ ] **Step 1: Write the test cases**

`parity/cases.json` — a minimum useful set of cases. Each exercises a different code path. Use small action sequences and seeds that produce reproducible results.

```json
[
  {
    "name": "trivial-roll",
    "seed": 1,
    "playerIds": ["P0", "P1"],
    "actions": [
      {"type": "ROLL"}
    ]
  },
  {
    "name": "roll-pick-stop",
    "seed": 7,
    "playerIds": ["P0", "P1"],
    "actions": [
      {"type": "ROLL"},
      {"type": "PICK", "face": 6},
      {"type": "STOP"}
    ]
  },
  {
    "name": "alternating-turns",
    "seed": 42,
    "playerIds": ["P0", "P1"],
    "actions": [
      {"type": "ROLL"},
      {"type": "STOP"},
      {"type": "ROLL"},
      {"type": "STOP"},
      {"type": "ROLL"},
      {"type": "STOP"}
    ]
  }
]
```

- [ ] **Step 2: Write the Node runner**

`parity/run-ts.mjs`:

```javascript
#!/usr/bin/env node
// Reads one parity case as JSON from stdin, emits the trace to stdout.
import { initialState, step } from '../src/engine.js';

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function actionFromDto(dto) {
  if (dto.type === 'ROLL') return { type: 'ROLL' };
  if (dto.type === 'STOP') return { type: 'STOP' };
  if (dto.type === 'PICK') return { type: 'PICK', face: dto.face };
  throw new Error(`unknown action type ${dto.type}`);
}

const raw = await new Promise((resolve) => {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => (buf += chunk));
  process.stdin.on('end', () => resolve(buf));
});
const testCase = JSON.parse(raw);
const rng = mulberry32(testCase.seed);
let state = initialState(testCase.playerIds);
const states = [state];
for (const dto of testCase.actions) {
  state = step(state, actionFromDto(dto), rng);
  states.push(state);
}
process.stdout.write(JSON.stringify({ states }));
```

Note: the TS engine source is TypeScript; the script uses tsx (the runner in `package.json`) which transpiles on the fly. We will invoke it as `tsx parity/run-ts.mjs`.

- [ ] **Step 3: Smoke-test the Node runner**

```bash
cd /Users/bramvanoost/Code/game-ching
echo '{"seed":1,"playerIds":["P0","P1"],"actions":[{"type":"ROLL"}]}' \
  | npx tsx parity/run-ts.mjs \
  | python3 -m json.tool | head -30
```
Expected: a JSON object with a `states` array of length 2.

- [ ] **Step 4: Write the README**

`parity/README.md`:

```markdown
# Cross-engine parity harness

Asserts byte-equivalent state traces between the TypeScript engine
(`src/engine.ts`) and the Swift engine (`ios/CHINGEngine`).

## Run

From repo root:

    node parity/diff.mjs

## Add a case

Edit `cases.json`. Each case is `{ name, seed, playerIds, actions[] }`.
Actions are `{ type: ROLL | PICK | STOP, face?: 1..6 }`. Coin face is 6.

Run the diff and verify both engines agree before committing the new case.
```

- [ ] **Step 5: Commit**

```bash
git add parity/
git commit -m "parity: ts runner + initial cases + readme"
```

---

## Task 17: Parity diff script

Drives both runners, normalizes outputs to a stable shape, and diffs them. Fails CI if they disagree.

**Files:**
- Create: `parity/diff.mjs`

- [ ] **Step 1: Write the diff script**

`parity/diff.mjs`:

```javascript
#!/usr/bin/env node
// Runs both engines on each case in cases.json. Asserts equal traces.

import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = dirname(__dirname);
const cases = JSON.parse(readFileSync(join(__dirname, 'cases.json'), 'utf8'));

const swiftCli = join(
  repoRoot,
  'ios/CHINGEngine/.build/debug/ching-parity'
);

function runTs(c) {
  const r = spawnSync('npx', ['tsx', join(__dirname, 'run-ts.mjs')], {
    input: JSON.stringify(c),
    encoding: 'utf8',
    cwd: repoRoot,
  });
  if (r.status !== 0) throw new Error(`ts runner failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

function runSwift(c) {
  const r = spawnSync(swiftCli, [], { input: JSON.stringify(c), encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`swift runner failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

// Normalize: the two engines may emit fields in different orders.
// Stringify with sorted keys for stable comparison.
function canon(obj) {
  if (Array.isArray(obj)) return obj.map(canon);
  if (obj && typeof obj === 'object') {
    const out = {};
    for (const k of Object.keys(obj).sort()) out[k] = canon(obj[k]);
    return out;
  }
  return obj;
}

let failed = 0;
for (const c of cases) {
  const ts = canon(runTs(c).states);
  const sw = canon(runSwift(c).states);
  const tsStr = JSON.stringify(ts);
  const swStr = JSON.stringify(sw);
  if (tsStr === swStr) {
    console.log(`OK   ${c.name}`);
  } else {
    failed++;
    console.error(`FAIL ${c.name}`);
    // Find first divergent state index for a useful error.
    for (let i = 0; i < Math.max(ts.length, sw.length); i++) {
      const a = JSON.stringify(ts[i]);
      const b = JSON.stringify(sw[i]);
      if (a !== b) {
        console.error(`  diverge at state[${i}]:`);
        console.error(`    ts:    ${a}`);
        console.error(`    swift: ${b}`);
        break;
      }
    }
  }
}

if (failed > 0) {
  console.error(`\n${failed}/${cases.length} parity cases failed`);
  process.exit(1);
}
console.log(`\n${cases.length}/${cases.length} parity cases passed`);
```

- [ ] **Step 2: Build the Swift CLI in release/debug as needed**

```bash
cd /Users/bramvanoost/Code/game-ching
(cd ios/CHINGEngine && swift build --product ching-parity)
```

- [ ] **Step 3: Run the diff**

```bash
node parity/diff.mjs
```
Expected: all cases print `OK`, summary line shows `3/3 passed`.

If a case fails: read the diverge-at-state[N] output. Likely culprits in order of probability:
1. RNG drift (verify Task 3 test still passes).
2. Phase transition difference in PICK auto-bank (Task 7).
3. Bust ordering of return-tile vs burn-highest (Task 6).
4. Steal-vs-center priority in tryBank (Task 9).

- [ ] **Step 4: Commit**

```bash
git add parity/
git commit -m "parity: diff script, all initial cases passing"
```

---

## Task 18: Expand parity case coverage

The three smoke cases pass. Add cases that exercise full game flows: PICK + ROLL chains, busts, steals, end-of-game. Each new case must pass before committing.

**Files:**
- Modify: `parity/cases.json`

- [ ] **Step 1: Add a deeper case that runs to game end**

Append to `parity/cases.json`. Use a sequence that drives a complete AI-vs-AI game by recording each action that `decide` would have produced for a known seed. The simplest approach:

1. Write a one-off Node helper inline below; it plays out an AI-vs-AI game with seed 1, low/high discipline as in `sim/regression.ts`, and records the action sequence.
2. Paste the recorded sequence as a new case.

Run this from repo root to generate the action list:

```bash
npx tsx -e '
import { initialState, step } from "./src/engine.js";
import { decide } from "./src/ai.js";

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(1);
let state = initialState(["P0", "P1"]);
const actions = [];
const discs = [0.2, 0.8];
while (state.phase !== "over") {
  const a = decide(state, { discipline: discs[state.current] });
  actions.push(a.type === "PICK" ? { type: "PICK", face: a.face } : { type: a.type });
  state = step(state, a, rng);
}
console.log(JSON.stringify(actions));
'
```

Take the JSON output, prepend a case header, and add to `cases.json` as a new array element:

```json
{
  "name": "full-game-seed-1",
  "seed": 1,
  "playerIds": ["P0", "P1"],
  "actions": [ ... PASTE ARRAY HERE ... ]
}
```

- [ ] **Step 2: Run the diff**

```bash
node parity/diff.mjs
```
Expected: 4/4 passes. If `full-game-seed-1` fails on a deep state: the divergence index pinpoints exactly which action caused the drift. Engine port is buggy at that step.

- [ ] **Step 3: Commit**

```bash
git add parity/
git commit -m "parity: add full-game case for seed 1"
```

---

## Task 19: GitHub Actions CI

Wire up CI so engine tests, parity tests, and sim regression all run on every PR.

**Files:**
- Create: `.github/workflows/engine-ci.yml`

- [ ] **Step 1: Write the workflow**

`.github/workflows/engine-ci.yml`:

```yaml
name: engine-ci

on:
  pull_request:
    paths:
      - 'src/engine.ts'
      - 'src/ai.ts'
      - 'sim/**'
      - 'ios/CHINGEngine/**'
      - 'parity/**'
      - '.github/workflows/engine-ci.yml'
  push:
    branches: [main]

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Use Swift 5.9
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: '5.9'

      - name: Use Node 22
        uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: Install npm deps (ts engine + tsx)
        run: npm ci

      - name: Run Swift engine tests
        run: cd ios/CHINGEngine && swift test

      - name: Run TS engine tests
        run: npm test

      - name: Build parity CLI
        run: cd ios/CHINGEngine && swift build --product ching-parity

      - name: Run parity diff
        run: node parity/diff.mjs

      - name: Run TS sim regression
        run: npm run sim
```

- [ ] **Step 2: Verify the workflow file is valid YAML**

```bash
cd /Users/bramvanoost/Code/game-ching
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/engine-ci.yml'))" && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Push to a feature branch and verify CI runs green**

```bash
git add .github/
git commit -m "ci: engine + ai + parity workflow"
```

Push to a branch and open a draft PR. Watch the CI tab; all four jobs should pass. If they fail, the error log will localize the issue.

(Do not merge yet; merge happens after this entire plan is reviewed by the user. The push is just to validate CI configuration.)

---

## Task 20: Phase 1 completion check

A short verification pass that asserts the phase is genuinely done.

- [ ] **Step 1: Run the full Swift test suite**

```bash
cd /Users/bramvanoost/Code/game-ching/ios/CHINGEngine && swift test
```
Expected: all tests pass (32+ test cases). Note total count for the completion checklist.

- [ ] **Step 2: Run the parity diff**

```bash
cd /Users/bramvanoost/Code/game-ching && node parity/diff.mjs
```
Expected: all 4 cases pass.

- [ ] **Step 3: Run the TS sim regression**

```bash
cd /Users/bramvanoost/Code/game-ching && npm run sim
```
Expected: terminates within step budget; higher discipline beats lower.

- [ ] **Step 4: Confirm no UI/UIKit/SwiftUI imports leaked into the engine package**

```bash
grep -rE '^import (UIKit|SwiftUI|AppKit)' ios/CHINGEngine/Sources && echo "FOUND, FIX" || echo "OK"
```
Expected: `OK`.

- [ ] **Step 5: Confirm engine purity (no Date/Math.random equivalents)**

```bash
grep -rE 'Date\(\)|Date\.|arc4random|drand48|UInt32\.random|\.random\(' ios/CHINGEngine/Sources && echo "FOUND, FIX" || echo "OK"
```
Expected: `OK`. (All randomness flows through injected `CHINGRandom`.)

- [ ] **Step 6: Confirm Phase 1 done**

If all five steps above pass, Phase 1 is complete. Update the brainstorm task list, commit any final touches, and notify the user that we're ready for Phase 2 (SwiftUI scaffolding).
