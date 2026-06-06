# Shell Yes UX pass, session handoff

**Written:** 2026-06-07
**By:** Claude (Opus 4.7)
**For:** the next Claude session that opens this repo
**Branch:** `shell-yes-rebrand` (not yet merged to main)
**HEAD:** `e730349`

## TL;DR for the next session

This session lived entirely on the `shell-yes-rebrand` branch (a continuation of the rename from "CHING" to "Shell Yes" with shells replacing coins). Two big things shipped: (1) the cityscape silhouette became a golden-hour Balearic beach; (2) a real UX bug — the Roll button mutating into Bank under your thumb — was fixed structurally by anchoring Bank to the running sum in the dice stage instead of having it share the bottom action bar.

Three open tasks remain on the visual rebrand list (see "Pending tasks"). The most-asked-for and never-started one is the **wordmark redesign**: Bram called the current "shell yes" lockup "meh" and asked for something design-y. Start there next session.

Before doing anything: read this doc, run the app, and ask Bram what to start with.

## What shipped this session

Commits on `shell-yes-rebrand`, in order:

1. **`398f1db` cityscape → golden-hour beach silhouette**
   `Background.swift` rewritten. Same `Background()` public API. New layers behind the sky gradient: far headland, sea band, tiny sailboat, dune with a warm lit crest, two procedural palms (curved trunks, fronds, leaning at different angles). Reuses `citySilhouette` / `citySilhouetteAccent` tokens, so dark mode still works.

2. **`d0dc96a` then `8193102` (reverted)** — tried adding compound-leaf feathered fronds to make palms less "cactus spiney". Bram said it was worse. Reverted. Current state is broad tapered fronds. The palm look is a known imperfect compromise but not blocking.

3. **`b353b2c` tap the sum to bank, so the bottom button never traps your thumb**
   This is the load-bearing change. Previously after picking, the bottom action bar split `Roll → [Roll Again | Bank]`, so a thumb resting where Roll lived now hit Bank. Solution: Bank is now anchored to the running sum *inside* `DiceStage`. When `canBank && isHumanTurn`, the sum number becomes a tappable card. The bottom action bar is single-button always (Roll, then Roll Again, same width and same position). Discussed three options with Bram (stacked, long-press, top-of-stage chip); he chose top-of-stage, and within that, "sum becomes the tap target" over "dedicated chip" because of mobile space constraints.

4. **`2aedbf6`, `d7986bc`, `a483d70`, `e4a484b`** — four iterations on the bank card visual after Bram pushed back. Landed on a compact two-tone receipt: cream half holds the sum (ink, 56pt italic Avenir DemiBold), coral gradient footer holds the bank label in cream stamp text + arrow. Capped at `maxWidth: 200pt`. Sits like a card, not a banner.

5. **`e4a484b` also killed the invite shine on in-game Roll/Roll Again.** The diagonal coral band Bram saw "running through the button" was the `invite` shine sweeping past at any opacity. Removed on the in-game button; splash New Game keeps it.

6. **`9b87c2c` roll animation no longer pre-flashes the final dice values**
   Real bug — the dice slot read `rolled` directly, so the body re-rendered once with the engine's final values before `.onChange` could set animation faces. Player saw the result for one frame, then watched the cycle land on those same values. Now the slot reads from a `@State displayedRolled` that's only updated inside the roll Task.

7. **`5050875` roll animation no longer permanently disables dice picks**
   Regression from #6: I gated picks on `isAnimating` derived from the task reference, but never cleared the reference. So after the first roll, you couldn't pick any face ever again. Fixed with a clean Bool flag flipped via `defer`.

8. **`e730349` drop monospacedDigit on the running sum**
   The kerning Bram noticed on "14"/"18" in the bank card was `.monospacedDigit()` padding narrow digits. Card width cap stabilizes layout without needing monospaced columns.

## Where the app is now

Run the simulator, tap New Game, play a turn. You should see:

- **Splash**: gold shell medallion, "shell yes" wordmark (the y in coral, 78pt ultraLight), tagline "they have shells. they could be your shells. score the shore.", New Game stamp button (with the soft invite shine pass), Settings link, Pixabay attribution.
- **Game**: chrome bar with "shell yes" + gear, scoreboard, safes grid, dice stage (phase hint + big sum + dice grid + locked slot), single Roll button at the bottom with comfortable home-indicator clearance.
- **After picking at least one die**: the sum number turns into a two-tone receipt card — cream-paper top holds the number, coral-gradient bottom says e.g. "BANK →" or "STEAL JONES'S TILE →". Tap it to bank. Bottom button is now "Roll Again", same width/position as Roll.

## Non-obvious decisions in this session

### Bank lives on the sum, not in the action bar
Three options proposed (stacked Roll+Bank, long-press Bank, top-of-stage chip). Chose top-of-stage because it's the only one that doesn't eat vertical space we don't have. Within "top-of-stage", "sum becomes the tap target" beat "dedicated chip beside the sum" because (a) it reuses the 84pt the hero number already owns and (b) it moves Bank out of the thumb zone entirely, which is the whole point. Don't undo this by stuffing Bank back into the action bar — the entire bug fix relies on the bottom button only ever meaning "throw the dice."

### Invite shine off in-game
The `StampButtonStyle(invite: true)` shine sweep is great on the splash New Game (it's a come-hither for first-use) but reads as a visible diagonal stripe at any opacity/width/tilt combination I tried. Once you're in the game you don't need the come-hither, so the in-game Roll uses `invite: false`. Don't re-enable it without solving the stripe problem (or replacing the animation entirely with something non-banded, like a soft text fade or border pulse).

### Roll animation: displayedRolled is the truth, not `rolled`
The dice slot used to render `rolled` (the engine's value). That meant SwiftUI rendered the final values for one frame before `.onChange` could install random animation frames, defeating the animation. The dice slot now renders a separate `@State displayedRolled` that lags behind `rolled` and is only updated by the animation task. Don't refactor this back to reading `rolled` directly. The Task uses `defer` to flip `isAnimating = false` and clear the task reference — the previous version forgot this and froze all picks.

### Palms have spikes, deliberately
Bram first asked for feathered fronds (added in `d0dc96a`) then said the result was worse than the spike version. So we reverted to broad tapered fronds. The palms aren't perfect but are off the immediate iterate list. If a future session wants to take another swing, do it in a separate branch and screenshot at the SAME canBank state Bram tests in so the comparison is apples-to-apples.

## Pending tasks (tracked in the in-session TaskList; carry over)

1. **Wordmark redesign (#93, in_progress)** — Bram's "shell yes" wordmark on the splash "looks meh"; he asked me to use plugins (visual companion / brainstorming) to redesign it. I never started. Options floated:
   - Shell-as-period ("shell yes◐")
   - Shell-as-S (shell glyph replaces "s" of "shell")
   - Stacked hero ("YES." huge with a shell-as-bullet)
   - Sub the medallion for a different lockup entirely
   Start with the brainstorming skill + visual companion (Bram has [[visual-companion-always]] on for this project).

2. **P5#2 Settings: rename bots** — let the player edit the AI names in Settings.

3. **P5#3 Stage container design (your roll + sum)** — partially addressed by the bank card work, but Bram may still want more treatment on the non-banking idle state.

4. **Finish the coin → shell rollout** — gold-circle `CoinPips` still appear on tile pips in `SafesGrid`, `VaultStack`, and `CountingCeremony` tile chips. `CountingCeremony.coinGlyph` (big total) and `GameView.redCoinGlyph` (cold bust coin) are still circles, not shells. Subsumed into the rebrand but never completed.

## Branch state, dev env

- Branch: `shell-yes-rebrand`, ahead of `main` by many commits.
- Tree clean as of `e730349`.
- All iOS tests pass: `GameStoreTests` (10/10), `SettingsStoreTests` (8/8). Engine + parity unaffected this session.
- Build target: iPhone 17 simulator, iOS 17+.
- Sounds: `farran_ez-minimal-piano-underscore-456148.mp3` (home theme), `dice_picking.m4a`, `dice_confirm.m4a`, `outcome-success.m4a`, `outcome-failure.m4a`. All wired through `HomeAudio` / `GameSFX` / `AudioPolicy` singletons with sound-mode setting (all/game-only/muted).

## Things to NOT do at the start of next session

- Don't merge `shell-yes-rebrand` to main without Bram saying so. The wordmark is still "meh" by his read and he may want more visual work before a merge.
- Don't undo the bank-on-sum architecture. It's the whole UX fix.
- Don't add an invite shine to the in-game Roll button.
- Don't re-add `.monospacedDigit()` to the sum without checking whether kerning regressed visibly.
- Don't try to fix palms unless asked — Bram said "we'll work on that : ) next?" and never came back to them.

## Quick verification

```bash
cd ios/CHING
xcodebuild -scheme CHING -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/ching-build build
xcrun simctl install booted /tmp/ching-build/Build/Products/Debug-iphonesimulator/CHING.app
xcrun simctl launch booted com.fastronaut.CHING
```

Splash should show the medallion, wordmark, beach silhouette at the bottom, New Game button with a soft shine pass. Tap New Game, roll a few times, pick a die — the running sum should turn into a two-tone receipt card. Tap it to bank.
