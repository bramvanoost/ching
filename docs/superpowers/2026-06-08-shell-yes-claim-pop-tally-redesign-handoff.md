# Shell Yes — claim chip pop+rays, bust ghost shell, tally row redesign, vault steal blink

**Written:** 2026-06-08
**By:** Claude (Opus 4.7, 1M)
**For:** the next Claude session
**Branch:** `theme-refinement` (still off `shell-yes-rebrand`, neither merged to main)
**HEAD before this session:** `8a008c0` — same uncommitted base as the earlier today handoff.
**Predecessors:**
- [[2026-06-07-shell-yes-ux-pass-handoff]]
- [[2026-06-07-shell-yes-testflight-prep-handoff]]
- [[2026-06-07-shell-yes-evening-aptabase-handoff]]
- [[2026-06-08-shell-yes-steal-animation-debug-menu-handoff]]
- [[2026-06-08-shell-yes-tally-active-card-bust-modal-handoff]] (the earlier today's session, where the tally festivity + bust modal landed)

## TL;DR

Six things landed, all sitting on top of the prior uncommitted work (nothing committed in this session yet):

1. **Claim modal chip pops in with a spring**, then a slow-rotating gold sunburst (`LightRays`) sits behind it. Sparkles were tried (radial + edge), both layers got removed — light rays read cleaner.
2. **Bust modal: ghost shell on the full-screen overlay** — `burnedTileChip` in `GameView` now uses the same dashed stroke + 0.85 opacity treatment as `AIEventBanner.ShellChip(drifting: true)`.
3. **Bust modal: redundancy fixed** — solo sand-burn no longer says "A shell drifts away" + chip labelled "sand" + "And the largest shell on the sand drifts away" for the same one shell. Combined the two-loss case into a single headline line.
4. **Tally screen redesigned to a horizontal leaderboard row** — name left, shells top-right, score+pearl bottom-right. Smaller digits (48→34) and pearl (48→24). Winner card gets a top-down gold gradient and a `LightRays` sunburst behind it. Sparkles removed entirely; "you win." headline now `.zIndex(10)` so rays never bleed over it.
5. **`LightRays` extracted to its own file** (`LightRays.swift`) — parameterised so both the claim chip (small subject) and the tally winner card (wide subject) can use it with different sizes.
6. **Vault steal pearl blink fix** — `VaultStack.safeView` no longer gates content via `.opacity(isTop ? 1 : 0)`. The previous gate had to animate 0→1 on the new top after a steal, which read as a stroke/pearl blink; z-occlusion from the existing `zIndex` already hides under-stack content, so the gate is redundant.
7. **Debug menu: "End game (tally screen)"** — new `debugForceGameOver()` on `GameStore` distributes a few shells, empties center, flips phase to `.over`. Wired into `ChromeBar`'s 🐞 menu.

Nothing committed yet. Modified files at session end: `AIEventBanner.swift`, `GameView.swift`, `GameStore.swift`, `CountingCeremony.swift`, `VaultStack.swift`, and the new `LightRays.swift`.

## What shipped this session

### Claim modal — pop animation + light rays behind the chip

`AIEventBanner.swift`.

**Bug found first.** Earlier today's session added `SparkleField(...).frame(width: 160, height: 160)` as a sibling of `ShellCardShape` inside `shellChip`'s ZStack. SwiftUI gotcha: a sized sibling forces the ZStack to that 160×160 intrinsic size, and `ShellCardShape` (which fills proposed space) rendered at 160×160 too. The outer `.frame(68, 84)` on the ZStack only sets the reported size — it doesn't shrink children that fill proposal. Result: the claim modal showed a giant card that clipped the headline "Nice, you claimed shell 23!" Fix was to lift sparkles to `.overlay { }` on the framed chip. **Worth remembering for future SwiftUI work**: explicit child frames inside a ZStack inflate that ZStack's intrinsic size; use `.overlay` or `.background` if you need decorations larger than the source view.

**Restructure to a stateful subview.** `shellChip` helper was inlined as a method on `AIEventBanner`. Extracted to `private struct ShellChip: View` so it can own a `@State popScale`. Otherwise the function couldn't hold the spring state.

**Pop animation.** `popScale` starts at `0.4`, springs to `1.0` on appear with `.spring(response: 0.32, dampingFraction: 0.5)`. Iterated three times — first attempt was `0.55` start / `response 0.45` / `damping 0.58` (Bram: "make it pop more, faster"), final tuning above lands with visible overshoot past 1.0 before settling.

**Sparkles — three rounds, ultimately removed.**
1. **Radial + edge layers** (`SparkleField` + `EdgeSparkleField`). Reported as "sparkles everywhere" — radial scatters particles through the rectangular shell silhouette, reading as background noise instead of "from the shell."
2. **Edge only** (count 56, inset 1, spread 48). Bram: still not shooting from the shell edge.
3. **All sparkles removed.** Bram's call: "forget the sparkles, just make it pop out a bit."

**`LightRays` for the claim chip.** After the pop landed cleanly, Bram asked for rays of light from behind the shell. Built `LightRays` as a `private struct` in `AIEventBanner.swift` initially: 12 capsules, gradient-faded at both tips (so they read as light, not solid spokes), `outerRadius: 92`, `rayWidth: 11` (later bumped to `18` per request), continuous 30s rotation, fade in 0.55s. Placed in `.background { if celebrate { LightRays() } }` — the inner portion of each ray is hidden behind the chip body, only the outer ends radiate beyond the silhouette. Inherits the chip's `.scaleEffect(popScale)`, so the halo grows with the pop.

**Gating.** Added a `celebrate: Bool` param back to `ShellChip`. Call site passes `celebrate: tone == .positive` for the claim chip, `celebrate: false` for the bust chip. So rays only fire on "you took" / "you stole" events.

### Bust modal — ghost-shell styling on the full-screen overlay

`GameView.burnedTileChip`.

Bram noticed: the AI-event-banner bust modal renders the burned shell with a dashed stroke and `.opacity(0.85)` (via `ShellChip(drifting: true)`), but the full-screen "Oh, shell no" overlay used a solid stroke for the same burned shell. Made `burnedTileChip` use the same visual language: `StrokeStyle(lineWidth: 2, dash: [3, 3])`, color softened to `Color.stampText.opacity(0.85)`, shadows dialed back (`coralDark @ 0.45` instead of `0.6`), and `.opacity(0.85)` on the chip frame.

### Bust modal — solo-burn redundancy fix + combined headline

`GameView.bustLossSection`.

**The bug.** When the bust burned a sand shell but the player had no top tile to lose (`returned == nil`, `burned != nil`), the modal rendered:
- "A shell drifts away." (header)
- [chip] labeled `sand`
- "And the largest shell on the sand drifts away." (trailing)

…all about the same single shell. `showSeparateBurn = burned != nil && !returnedIsBurned` was true whenever there was a burn, including the solo-burn case.

**Fix.** Renamed to `twoLosses = returned != nil && burned != nil && !returnedIsBurned`. Now the trailing line and the `yours`/`sand` chip labels only render when there are genuinely two distinct shells to distinguish. Solo-burn collapses to header + one unlabeled chip. Also added an `else if let burned` fallback so the chip still renders in the no-returned case (otherwise the chip would disappear with `twoLosses == false`).

**Then headline merge.** Bram asked to combine the two-loss copy into the top line. New construction: a `let headline: String = { ... }()` closure outside the ViewBuilder (ViewBuilder doesn't allow if/else assignment to a `let`), three branches:
- `twoLosses`: "You lose your top shell, and the largest shell on the sand drifts away."
- `returned != nil`: "You lose your top shell."
- otherwise: "A shell drifts away."

Trailing `Text` block gone. Chip labels (`yours`/`sand`) preserved in the two-loss case so the side-by-side chips remain individually identifiable.

### Tally screen — horizontal leaderboard rows

`CountingCeremony.swift`.

**Layout pivot.** Previous design was a centered three-row stack per card (Name / shells row / big score+pearl). Bram: "last card and New Game are almost overlapping; name on the left, right top shells, right bottom number and pearl, use your design skills."

New `playerCard` is `HStack(alignment: .center, spacing: 14)`:
- **Name** left-anchored, `.avenir(22, weight: isWinner ? .demiBold : .medium, italic: true)`, `lineLimit(1)`, `minimumScaleFactor(0.7)`.
- **Spacer(minLength: 8)** so cards with long names don't crowd the right column.
- **Right column** `VStack(alignment: .trailing, spacing: 8)` — shells row on top (or `Text("no shells")` italic with `frame(height: 40)` to keep right column baseline consistent for empty seats), then score+pearl.

**Score+pearl sizing.** 48pt → 34pt for the digit, 48pt → 24pt for the pearl. Frees the vertical room the user reported was disappearing under the New Game button.

**Pearl alignment.** First pass used `firstTextBaseline` + a custom `alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 8 }`. Bram: pearl needs to go up a bit. Switched to `HStack(alignment: .center, spacing: 6)` with `.offset(y: -3)` on the pearl. Comment in the code explains why: italic digits carry their visual mass above center, so a true vertical center reads as low.

**Winner card gradient.** Was flat `Color.gold.opacity(0.28)`. Replaced with a top-to-bottom `LinearGradient`:
```
[Color.coinGoldLight.opacity(0.55),
 Color.gold.opacity(0.32),
 Color.gold.opacity(0.18)]
```
Extracted into `winnerOrIdleFill(isWinner:)` returning `AnyShapeStyle` (lets the same `.background(RoundedRectangle.fill(...))` handle both winner and idle paths cleanly).

**Rays of light behind the winner card.** `LightRays` (now shared) placed in a SECOND `.background { }` AFTER the gradient fill — so the rays render furthest back, the gradient covers the inner portion, and only the outer rays radiate beyond the card silhouette. First sizing was `outerRadius: 220, rayWidth: 28` to clear the full card width on iPhone; reduced to `outerRadius: 150, rayWidth: 24, maxOpacity: 0.5` after Bram reported the rays were bleeding into the "you win." headline area above. Slower rotation `36s` (vs 30s on the chip) since the larger sweep would otherwise feel busy.

**Sparkles removed entirely.** Was `EdgeSparkleField(count: 130, inset: 0, spread: 80, duration: 1.1)` from earlier today's session. Bram: "they still don't cover the winner tile." With the new compact card and the light rays doing the celebration work, sparkles were redundant — and the radial `SparkleField(count: 36, startRadius: 14, ...)` that was previously stacked on top scattered through the card body anyway.

**"You win." `.zIndex(10)`.** WinHeadline sat in a sibling-ish position above the cards. The light rays from the winner card (no clip) extended up far enough to visually compete with the headline. zIndex pins the headline to the top of the stacking order. Also dropped the `SparkleField` overlay on the headline itself (was firing on its own `humanWinHeadlineSparkle` cadence) — same "sparkles everywhere" objection applies.

### `LightRays` extracted to a shared file

`LightRays.swift` (new). Was a `private struct` inside `AIEventBanner.swift`; both the claim chip and the tally winner card now need it. Parameters all exposed: `rayCount`, `innerRadius`, `outerRadius`, `rayWidth`, `rotationDuration`, `maxOpacity`. Defaults match the chip's use case (`outerRadius: 92, rayWidth: 18, ...`), the tally site passes its own larger sizing.

Note: Xcode project uses a `PBXFileSystemSynchronizedRootGroup`, so the new file is auto-discovered — no `project.pbxproj` edit needed. Confirmed by `grep "SparkleField" project.pbxproj` returning 0.

### Vault steal — pearl/stroke blink fix

`VaultStack.safeView`.

**History.** Two sessions ago (the steal animation session) the bug was: when the top shell of a stack is stolen, the new top's content "popped in" because `safeView` used `if isTop { content }`. That session fixed it with `.opacity(isTop ? 1 : 0)`, expecting the parent's `.animation(.easeOut(duration: 0.32), value: safes.count)` to smoothly fade 0→1.

**The fade never quite worked.** Bram still saw pearls/stroke blink during a steal. Root cause: the `isTop` flip is a *derived* prop change (the ForEach re-keys the surviving view from `idx: 1, isTop: false` to `idx: 0, isTop: true`), and SwiftUI's `.animation(value: safes.count)` doesn't reliably animate prop-driven changes that come through a re-keyed identity in the same render frame.

**Fix.** Removed the opacity gate entirely. Content (text + pearls) now renders unconditionally on every shell. The existing `.zIndex(Double(stackedNewestFirst.count - idx))` on the ForEach z-occludes under-stack content behind the top card, so the visual stack is identical when nothing is changing. When a steal removes the top, the surviving shell is simply *un-occluded* as the old top's `.opacity` removal transition fades it out — no visibility flip means no blink. Also dropped the now-unused `isTop:` parameter from `safeView`.

**Important context if this comes back.** If a future change re-introduces lower-shell content peek-through (e.g., adjusting `layerOffset` or `maxVisible`), the natural occlusion assumption breaks. The fix then should NOT be to re-add the opacity gate — instead either:
- Mask the lower shells via `.mask(ShellCardShape().offset(...))` to clip content under the top card, or
- Use the `.opacity(isTop ? 1 : 0)` gate *but* drive the animation via `withAnimation { ... }` from the steal action site (in `GameView.act`), not via the parent's `value:` modifier.

### Debug — "End game (tally screen)" shortcut

`GameStore.debugForceGameOver()` + `ChromeBar` menu item.

The brief was "how can we simulate the end screen?" Answer: a new debug action that distributes a small fistful of shells (human gets 4, AI seats 2 each — gives the human a believable win to celebrate), empties `centerTiles`, clears all dice/picked/setAside state, and sets `state.phase = .over`. Wired into `ChromeBar`'s `Menu` as the third item (after Seed AI vaults and Trigger steal), `systemImage: "flag.checkered"`. `ChromeBar` got a third `onDebugEndGame: (() -> Void)?` closure prop.

Behind `#if DEBUG` everywhere — won't ship in release.

## Files touched

```
AIEventBanner.swift       — ShellChip subview, pop animation, LightRays extracted out
GameView.swift            — burnedTileChip ghost styling, bustLossSection rewrite,
                             ChromeBar onDebugEndGame wiring
GameStore.swift           — debugForceGameOver()
CountingCeremony.swift    — full playerCard redesign, winnerOrIdleFill, zIndex headline,
                             LightRays background
VaultStack.swift          — removed .opacity(isTop ? 1 : 0), removed isTop param
LightRays.swift           — NEW. Shared parameterised light rays component
```

## SwiftUI gotchas hit this session (keep handy)

1. **Sized siblings inflate ZStack intrinsic size.** `ShellCardShape` (fills proposed) inside a ZStack alongside `SparkleField().frame(160, 160)` rendered at 160×160 too, even with an outer `.frame(68, 84)` on the ZStack. Use `.overlay` / `.background` for decorations that need their own larger frame.
2. **Prop-driven changes after a ForEach re-key don't always animate** under `.animation(value: someState)`. If you need a smooth animation on a re-keyed view's changing prop, drive the change via `withAnimation` at the mutation site, or restructure to avoid the visibility flip entirely (z-occlusion / masking).
3. **`.background` and `.overlay` don't clip.** Light rays sized larger than the source view extend beyond the source's bounds — handy when you want a halo, dangerous when adjacent siblings get visually trampled. Use `.clipped()` if you need containment, or reduce the decoration size.
4. **ViewBuilder doesn't accept `if/else if/else` for assignment to a `let`.** Wrap in an immediately-invoked closure: `let x: T = { if ... { return ... }; return ... }()`.
5. **Xcode `PBXFileSystemSynchronizedRootGroup` projects auto-pick up new Swift files** in the source directory. No `project.pbxproj` edit needed.

## What's next

Nothing pre-committed for the next session. Likely candidates:

- **Verify all of this on device** — every change builds, none have been seen on hardware in this session. Bram has been verifying on simulator/iPhone manually between rounds.
- **Commit** — six logical units, could be one commit or split into:
  1. Claim chip pop + light rays (AIEventBanner + LightRays.swift)
  2. Bust modal ghost shell + combined headline (GameView)
  3. Tally redesign (CountingCeremony)
  4. Vault steal blink fix (VaultStack)
  5. Debug end-game shortcut (GameStore + GameView ChromeBar)
- **TestFlight still blocked** — Apple Dev Program enrollment still pending on Belgian ID verification (see prior handoffs).
- **Telemetry check** — none of these changes added or removed Aptabase events. `game_bank`, `game_bust`, `game_steal`, `game_ended` all still firing from the same places. Aptabase debug-vs-release split memory still applies.

## Memory crumbs worth knowing

- Bram explicitly prefers tappable playable progress over engine rigor on this project (see `playable-over-rigor.md`).
- Pop bolder than restraint on CHING (see `ching-pop-over-restraint.md`) — this session leaned into that with the spring pop and the light rays.
- Telemetry update checklist applies to every Shell Yes change. None of this session's changes affected events, but worth a re-check if anything gets bundled with logic changes during commit.
