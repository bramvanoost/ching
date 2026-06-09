# Shell Yes — steal animation, dice tally, debug menu, claim-modal sparkles

**Written:** 2026-06-08 (afternoon, second session of the day)
**By:** Claude (Opus 4.7, 1M)
**For:** the next Claude session
**Branch:** `theme-refinement` (still off `shell-yes-rebrand`, neither merged to main)
**HEAD before this session:** `8a008c0` — `ux: tally festivity, active-card glow, bust modal, per-mode stats`
**Predecessor:** [[2026-06-08-shell-yes-tally-active-card-bust-modal-handoff]]

## TL;DR

All changes uncommitted. Most of the session went well; the last step (claim-modal sparkles) broke layout and the sparkles fire at the wrong positions — Bram called the restart there.

What's done and verified:
1. **Telemetry: `game_won` / `game_lost`** fire alongside `game_ended` so the dashboard gets dedicated win/loss event counts instead of needing a `won = true` filter on every panel. Same props on all three. `Analytics.md` updated.
2. **Phase hint copy** — `"no rush, smell the sea air"` → `"your turn. deep breath."` (Bram's wording).
3. **Dice "N in hand" tally** — visualised as filled `lockedDie`s + small hollow rounded squares (10pt, 2.5pt corner radius) in the locked row. Replaced an earlier text label that was getting cropped on 5+ locked dice and looked tacked-on next to the phase hint.
4. **Steal animation** — `SmokePoof` on the victim's vault + staged sparkle / scale-in on the receiver's vault 450ms later. Multiple flicker bugs hunted down (see "the steal-animation rabbit hole" below).
5. **Debug ladybug menu** — `ChromeBar` (DEBUG only) now has a small coral ladybug → menu with `Seed AI vaults (+2 each)` and `Trigger steal`. Used to verify the steal flow without playing through.

What's broken at session end:
6. **Claim-modal sparkles** — added `SparkleField` + `EdgeSparkleField` overlays to `AIEventBanner.shellChip` when `tone == .positive`. Bram's verdict: **"UI is off and sparkles are flying at random."** Compile-clean, behaviour wrong. **Start the next session here.**

## Files touched

```
ios/ShellYes/ShellYes/AIEventBanner.swift   # claim-modal sparkles (BROKEN)
ios/ShellYes/ShellYes/DiceStage.swift       # mini-square tally row
ios/ShellYes/ShellYes/GameStore.swift       # debug helpers, phase hint copy
ios/ShellYes/ShellYes/GameView.swift        # game_won/lost, stealArrivalSeat staging, ChromeBar wiring
ios/ShellYes/ShellYes/Scoreboard.swift      # poofTriggers, ZStack(.top), layered placeholder
ios/ShellYes/ShellYes/VaultStack.swift      # ForEach id .element, opacity isTop, always-render body
ios/ShellYes/ShellYes/SmokePoof.swift       # NEW
```

External:
```
Obsidian Vault/Projects/Shell Yes/Analytics.md   # game_won/lost section + updated event-name row + new starter query
```

## What shipped this session

### 1. Telemetry: `game_won` / `game_lost` alongside `game_ended`

`GameView.swift:531-545` (the `.onChange(of: store.isOver)` block).

Bram played a game, won, and asked "where's the game won event?" — there wasn't one; only `game_ended` with a `won` boolean prop. He wanted dedicated outcome events. Discussed three options via AskUserQuestion; he picked **"Keep game_ended, add game_won/game_lost alongside"** so existing dashboards aren't disrupted and outcome cards become trivial.

Implementation: build the props dictionary once, fire `game_ended` always, then fire `game_won` or `game_lost` with the same props.

```swift
let endProps: [String: Any] = [
    "won": humanWon,
    "my_score": humanScore,
    "opponent_count": store.state.players.count - 1,
    "busts": bustsThisGame,
    "steals": stealsThisGame,
    "biggest_keep": biggestKeepThisGame,
    "duration_seconds": duration,
    "difficulty": settings.difficulty.rawValue,
    "pace": settings.gameSpeed.rawValue,
]
Telemetry.shared.track("game_ended", props: endProps)
Telemetry.shared.track(humanWon ? "game_won" : "game_lost", props: endProps)
```

Per the `telemetry-update-checklist` memory, `Analytics.md` updated in the same change: new `game_won` / `game_lost` section, schema event-name row extended, starter "win rate by difficulty" query rewritten to use the cleaner event names.

Bram is **pre-TestFlight** (Apple Dev Program enrollment still blocked on Belgian ID verification). All current data is in the Debug stream. He knows the dashboard reset story for TestFlight day (per `shell-yes-debug-vs-release-aptabase` memory).

### 2. Phase hint copy

`GameStore.swift:106`. Trivial — one-line copy change Bram asked for.

```swift
return state.setAside.isEmpty ? "your turn. deep breath." : "roll on, or keep."
```

### 3. Dice "N in hand" tally — the mini-square row

`DiceStage.swift`. The user wanted to see how many dice are still throwable during a turn (`diceInHand`, max 8 = `TOTAL_DICE`).

Three attempts before landing:

**Attempt 1 — inline with locked row.** Right-side `Text("\(diceInHand) in hand")` in the same `HStack` as the locked dice. **Broke when locked had 5+ dice:** the locked-dice group + label couldn't fit iPhone width, SwiftUI compressed the locked group and the dice disappeared from view. Bram: "after four or so dice, the locked disappears."

**Attempt 2 — top-right next to phase hint.** Pinned to the trailing edge of the phase-hint row via a `ZStack` so it never competed with the locked row. **Bram rejected:** "Too close to the message above the score now, and not aligned (bottom). I think top right is not a great location for amount of dice left." Then: "Use your design skills?"

**Attempt 3 (current) — visual tally in the locked row.** Skipped the `AskUserQuestion` second-guess and committed to a stronger idea: render locked dice on the left with face values, then small hollow squares on the right for the remaining `diceInHand` slots. Bram: "I see what you did there! Smart." Then asked to switch the placeholders from circles to mini rounded squares so they look like dice silhouettes:

```swift
ForEach(0..<diceInHand, id: \.self) { _ in
    RoundedRectangle(cornerRadius: 2.5)
        .strokeBorder(Color.ink.opacity(0.45), lineWidth: 1.2)
        .frame(width: 10, height: 10)
}
```

Pre-existing `Color.clear.frame(width: 4, height: 1)` sits between locked group and hollow group as a visual gap when both are present. The row's `.opacity(locked.isEmpty && diceInHand == 0 ? 0 : 1)` keeps it invisible when there's nothing to show.

### 4. The steal animation rabbit hole

This took most of the session. Five round trips with Bram. The order matters — each fix surfaced the next bug.

**Goal:** when a shell is stolen, the victim's vault shows a *poof* of smoke, the receiver's vault shows the new shell appearing with sparkles, **and the two read as sequential** ("lost there → arrived here") rather than simultaneous.

#### 4a. `SmokePoof` (new file)

`SmokePoof.swift`. Soft cream puffs (7 by default), each a `Circle` filled with a warm chalk colour `(245, 232, 218)`, `blur(radius: 4)`, drifting outward and **upward-biased** (smoke rises) over 0.75s. Particles use a deterministic seed → angle/distance pattern (same idea as `SparkleField`). Hard-coded chalk colour rather than `Color.paper` because the latter inverts in dark mode to deep plum, which would read as a dark smear not smoke.

Wired into `Scoreboard.swift` via a per-seat `poofTriggers: [Int: Int]` dictionary that increments on `.onChange(of: stolenFrom)`. Lives **at the column ZStack level**, not on `VaultStack`, so it still renders if the last shell is taken (the stack collapses to placeholder but the poof needs to still fire over the now-empty slot).

Size: **40×40 frame** (matches `safeHeight = 38`) so the burst centres on the disappearing top shell rather than on the column.

#### 4b. Receiver staging — `stealArrivalSeat`

The receiver's sparkle was firing at the same instant as the victim's poof. Bram wanted them sequential. Solution: a `@State var stealArrivalSeat: Int?` in `GameView` and a `displayedPlayers` computed property that shows the receiver's `tiles` array minus the last element while staging is active.

```swift
private var displayedPlayers: [Player] {
    guard let seat = stealArrivalSeat else { return store.state.players }
    var players = store.state.players
    guard players.indices.contains(seat), !players[seat].tiles.isEmpty else {
        return store.state.players
    }
    players[seat].tiles.removeLast()
    return players
}
```

Pass `displayedPlayers` to `Scoreboard` instead of `store.state.players`. `Scoreboard.scores` is still real-time but that prop has an unused `pearlCount` binding — no visible effect.

Staging is cleared by a 450ms `Task.sleep`. When cleared, `VaultStack.onChange(of: safes.count)` finally sees the increment and fires its existing `addSparkleTrigger`. Choreography:
- T+0: smoke poof on victim, victim stack shrinks
- T+450: sparkle + tile pop-in on receiver

#### 4c. "Why does the stolen-from stack go down first?"

Bram observed the victim's vault sliding down a few pixels before settling. Cause: the column's `ZStack` used **default centre alignment**. When `VaultStack`'s `stackHeight` shrank (53→48pt after losing a shell), SwiftUI re-centred the smaller frame inside the 54pt slot — top edge moved down ~2.5pt and bottom edge moved up ~2.5pt while the spring settled.

Fix in `Scoreboard.swift`: `ZStack(alignment: .top)` and recheck of the entire column. Verified the smoke-poof frame was 70×70 and centred on the column rather than the shell — shrunk it to 40×40 so the burst origin matches the disappearing top.

Also softened the vault spring at the same time. `VaultStack.swift`:

```swift
// Layout (height) change uses a calm easeOut so removals
// don't overshoot — the springy "pop" is reserved for the
// insertion transition above, where it reads as celebration
// rather than the stack settling after a loss.
.animation(.easeOut(duration: 0.32), value: safes.count)
```

Insertion still keeps a spring on the transition itself:
```swift
insertion: .scale(scale: 0.15)
    .combined(with: .opacity)
    .animation(.spring(response: 0.55, dampingFraction: 0.6)),
removal: .opacity.animation(.easeOut(duration: 0.28))
```

#### 4d. "The target stack has two animations"

After the staging fix, Bram saw two distinct animations on the receiver: one at T+0 (when victim poofed), another at T+450 (the staged sparkle).

Diagnosis: the engine advances `state.current` immediately after the human banks/steals. The human column's `isActive` flipped true→false at T+0, triggering its scale (1.03→1.0) + offset (-2→0) spring. Then the staged sparkle landed at T+450.

Fix: extend `displayCurrent` to hold on the receiver during staging:

```swift
private var displayCurrent: Int {
    if let frozen = bustFrozenCurrent { return frozen }
    if let arrival = stealArrivalSeat { return arrival }
    return store.state.current
}
```

#### 4e. "Target stack STILL has 2 animations — one fires when the victim poofs"

The `displayCurrent` fix wasn't enough. Cause: `detectSteal` runs via `.onChange(of: store.state.players.map { $0.tiles.count })`, which fires **after** SwiftUI has already rendered the post-bank state once (active→inactive transition started). The next render with `stealArrivalSeat` set would reverse the transition — a brief flicker reading as an animation.

Fix: set `stealArrivalSeat` **synchronously alongside the state change** so SwiftUI batches both into one render. Two places needed it:
- `act()` in `GameView.swift:218-222` (real gameplay): inside the `if let victim` branch, set staging right before `store.presentTurnEvent`.
- Debug "Trigger steal" callback: set staging **before** calling `store.debugTriggerSteal()`, both inside the same `Task @MainActor` block.

Both also spawn their own clearing Tasks. `detectSteal` still sets `stealArrivalSeat` later (idempotent — same value, the second clearing Task no-ops because the first one already cleared it). Left in for the AI-steals-from-human case where there's no `act()` path.

#### 4f. "Stroke around the pearl on the stolen pile blinks"

After all the timing fixes, Bram saw a stroke flicker on the victim's promoted shell at the end of the animation.

Cause (first try): `VaultStack` keyed its `ForEach` by `\.offset`. When the top tile was removed, every remaining shell got a NEW value at its old position — same view identity, new content (Text value + PearlRow). SwiftUI re-rendered them mid-animation, strokes/anti-aliasing flickered.

Fix: key by **tile value** instead. Tiles 21–36 are unique per game (engine guarantee, also documented in `CLAUDE.md`), so each view's identity stays stable across count changes. The removed shell is the one that animates out; the others just shift position.

```swift
ForEach(Array(stackedNewestFirst.enumerated()), id: \.element) { idx, safe in
    safeView(value: safe, isTop: idx == 0)
    ...
}
```

Bram: "Works! The pearls still blink on the stolen pile. The stroke, I think. At the end of the animation, possibly."

Cause (second try): the promoted shell's content was inside `if isTop { VStack... }`. When `isTop` flipped false→true (because the shell above was removed), the entire `VStack` was structurally inserted into the view tree — no transition, instant. Then at animation completion the layer rasterised, causing the perceived end-of-animation snap.

Fix: always render the content, toggle `opacity(isTop ? 1 : 0)`. The content fades in under the parent's `easeOut(0.32)` animation when `isTop` flips. Smooth, no snap.

```swift
VStack(spacing: 2) {
    Text("\(value)")...
    PearlRow(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
}
.opacity(isTop ? 1 : 0)
```

Bram: "Works!"

#### 4g. "Stealing into an empty target doesn't trigger the appearance animation"

The receiver's vault was empty before the steal. Scoreboard's column was rendering `safePlaceholder()` instead of `VaultStack` via `if players[i].tiles.isEmpty { safePlaceholder() } else { VaultStack(...) }`. When the tile arrived, SwiftUI swapped view identities, creating a fresh `VaultStack`. Fresh `VaultStack` doesn't fire `.onChange(of: safes.count)` (no transition from 0→1, just an initial state), and the `ForEach` element is "initial" rather than "inserted" — no sparkle, no scale-in.

Fix in two places:

**`Scoreboard.swift`** — layer placeholder over VaultStack with opacity instead of swapping:
```swift
ZStack(alignment: .top) {
    safePlaceholder()
        .opacity(players[i].tiles.isEmpty ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: players[i].tiles.isEmpty)

    VaultStack(safes: players[i].tiles, activeSeat: isActive)

    if let trigger = poofTriggers[i], trigger > 0 {
        SmokePoof().frame(width: 40, height: 40).id(trigger)
    }
}
.frame(height: 54, alignment: .top)
```

**`VaultStack.swift`** — always return the `ZStack` body (no `if safes.isEmpty { EmptyView() } else { ... }`). When empty, the `ForEach` just renders nothing.

### 5. Debug ladybug menu

Bram asked "how can we see this?" partway through the steal-animation work. Added two DEBUG-only helpers on `GameStore`:

```swift
#if DEBUG
func debugSeedAIVaults() {
    // Pull 2 random tiles from centerTiles into each non-human seat's
    // vault. Uses Int.random because this is a debug helper, not the
    // engine — engine purity isn't violated.
}

func debugTriggerSteal() {
    // Move the top tile from the first non-human seat with shells into
    // the human's vault. If no AI has any, seed one with tile 25 first.
}
#endif
```

`ChromeBar` (in `GameView.swift`) renders a small coral ladybug icon in `#if DEBUG`, opens a `Menu` with the two actions. Both callbacks wait 250ms before mutating state so the menu's dismiss animation completes first — Bram observed the animation firing under the closing menu modal otherwise.

The "Trigger steal" callback also sets `stealArrivalSeat` synchronously before calling `store.debugTriggerSteal()` (same trick as the real `act()` path).

### 6. Claim-modal sparkles — BROKEN

`AIEventBanner.swift`. Bram's ask:

> When claiming a shell as a user, a modal appears with the claimed shell, lets add some sparks to that shell in the modal to emphasize the win.

Approach: added `celebrate: Bool` parameter to the existing `shellChip` function, computed `celebrate = tone == .positive` at the call site, layered two effects inside the `shellChip`'s `ZStack`:

```swift
if celebrate {
    SparkleField(count: 56, startRadius: 36, spread: 95, duration: 1.4)
        .frame(width: 160, height: 160)
        .allowsHitTesting(false)

    EdgeSparkleField(count: 36, inset: 2, spread: 14, duration: 1.3)
        .allowsHitTesting(false)
}
```

Bram's response: **"UI is off and sparkles are flying at random."** Compile-clean, but visually wrong.

## Start here next session

**The claim-modal sparkles, `AIEventBanner.shellChip` celebrate branch.**

Hypotheses to investigate (no screenshot yet, so each is a guess):

1. **The 160×160 SparkleField frame breaks layout.** The chip's outer `.frame(width: 68, height: 84)` clips the ZStack, so the 160×160 SparkleField gets clamped to 68×84 — but **before clipping** its layout participation may push the chip's parent layout (the `VStack` in the modal body) outward. Try moving the SparkleField to an `.overlay(alignment: .center)` on the chip *outside* the inner ZStack, with `.allowsHitTesting(false)` and `.compositingGroup()`. Or set the 160×160 frame and follow with `.fixedSize()` so the SparkleField doesn't influence parent sizing.

2. **`SparkleField` uses `.offset(...)` from its own centre.** Particles spread from the centre of the SparkleField's frame. If the SparkleField is laid out somewhere unexpected (e.g. above the shell rather than over it), particles emanate from the wrong origin → "flying at random" relative to the shell. Check geometry alignment.

3. **`EdgeSparkleField` reads the *host frame size* via `GeometryReader`** (`SparkleField.swift:101-120`). If it ends up reading the 68×84 chip frame vs the 160×160 SparkleField frame vs something larger, the edge walk lands at wildly different perimeter coordinates. Possibly the EdgeSparkleField's host is the entire modal card, not the shell — that would produce sparkles "all over the place."

4. **Both fields fire on `.onAppear` (their `go` flag toggles via `withAnimation { go = true }`).** The modal appears via SwiftUI transition, so `.onAppear` fires once — that should be fine. But if SwiftUI is also re-laying out mid-transition, the seed→position math may be applied to an intermediate frame. Test by adding `.transaction { $0.animation = nil }` on the sparkle overlays so they pin geometry before animating.

5. **The chip-level `.shadow(color: Color.coralDark.opacity(0.2), radius: 14, ...)` may interact with `.blendMode(.plusLighter)` on the sparkle glyphs** in unexpected ways. Less likely but worth ruling out.

Suggested fix order:
1. Move sparkles to an `.overlay` on the chip with `.allowsHitTesting(false)`, NOT inside the chip's own ZStack.
2. Constrain the frame to the chip's footprint (68×84) so EdgeSparkleField reads the right perimeter; render only `SparkleField` (drop the `EdgeSparkleField` for now — it's the more error-prone of the two).
3. If positions still look off, hard-code the SparkleField frame and use `.position(x: chipWidth/2, y: chipHeight/2)` to pin its centre.

**Acceptance from Bram:** "emphasize the win" — wants sparkles that read as bursting from the won shell, not random particles scattered across the modal. Reserve sparkles for `tone == .positive` (you took/stole). AI claims (`.neutral`) and AI-steals-from-you (`.negative`) and busts stay sparkle-free.

## Non-obvious decisions worth preserving

- **`SmokePoof` colour is hard-coded** (cream `(245, 232, 218)`), not `Color.paper` — `paper` inverts in dark mode and "dark smoke" reads as a smudge, not steam.
- **`SmokePoof` renders at column-ZStack level**, not on `VaultStack`. Necessary for the last-shell-taken case where `VaultStack` collapses to placeholder; the poof needs to still appear over the now-empty slot.
- **`stealArrivalSeat` is set synchronously in `act()` and the debug closure**, not deferred via `.onChange`. SwiftUI batches synchronous state changes into one render — `.onChange` runs after the first post-change render, which is one render too late to prevent the active-state flicker.
- **`displayedPlayers` trims the receiver's last tile** rather than holding the entire `players` array stale. Lets the victim's loss animate immediately (poof + stack collapse) while only the gain side is delayed.
- **`VaultStack.ForEach` keys by tile value (`\.element`)**, not array offset. Tiles 21–36 are unique within a game; this keeps view identity stable so the *removed* shell animates out rather than every shell re-rendering with a swapped value. Bram saw stroke flicker before this fix.
- **`VaultStack` always returns its body** (no `if safes.isEmpty { EmptyView() }`). Required so `.onChange(of: safes.count)` fires on the 0→1 transition; combined with the placeholder being layered (not swapped) in `Scoreboard`.
- **Vault layout uses `easeOut(0.32)` for `safes.count`**, the insertion transition has its own spring. Mixed-animation pattern: smooth removals, springy additions. Don't collapse them back into a single spring unless you also keep removals critically damped — bouncy removals read as "stack overshoots after a loss" which felt wrong to Bram.
- **The dice tally row is intentionally width-bounded by tiny squares** (10pt) rather than full dice. An 8-die haul of locked dice already nearly fills iPhone width; if remaining slots were full-size they'd push the row off-screen.

## Build / commit state

- `xcodebuild -scheme ShellYes -destination 'platform=iOS Simulator,name=iPhone 17' build` is **clean** at session end (only pre-existing `didBank` and `pearlCount` unused-variable warnings).
- **Nothing is committed.** The whole session's work is staged on `theme-refinement` locally.
- The claim-modal sparkles compile but don't render where they should — decide whether to revert that file or push through the fix at the start of the next session.
