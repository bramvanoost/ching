# Theme & copy refinement — 2026-06-07

Scope: iOS app (`ios/CHING/CHING/*.swift`). Copy, two-noun model, pearl visual,
shell-card tile geometry. No engine, scoring, probability, steal, or stacking
rule changes.

## 1. Two-noun model

| Concept           | Before                | After (UI)         |
|-------------------|-----------------------|--------------------|
| Claimed object    | "tile" / "safe"       | **shell**          |
| Points-token      | gold "coin" pip       | **golden pearl**   |
| Wildcard die face | "coin" face / shell medallion | **pearl** face / Pearl glyph |
| Player total      | "X tiles"             | **X pearls**       |

Engine code keeps `tile` / `safe` identifiers. The model split lives at the UI
layer only: `Player.tiles` still returns the same array, but every user-facing
label that referred to them is now "shell". The points-token visual was a flat
gold dot; it is now a pearlescent golden pearl.

Score display switched from counting **shells** to counting **pearls**. Engine
`score(state)` already returns total worms (= total pearls), so this was a
label change, not a math change.

## 2. Copy swaps (calm tone, no exclamation marks in-game)

| Location                                       | Before                              | After                            |
|------------------------------------------------|-------------------------------------|----------------------------------|
| `SplashView.swift:46`                          | they have shells. … score the shore. | soft maths, golden light.        |
| `SafesGrid.swift:16`                           | tiles left to steal                  | shells on the sand               |
| `GameStore.swift:67-80` phaseHint (your turn) | You're up. Roll the dice.            | no rush. read the tide.          |
| phaseHint (mid-turn)                           | Roll again, or bank.                 | roll on, or keep.                |
| phaseHint (pick)                               | Choose wisely.                       | pick what you'll keep.           |
| phaseHint (game over)                          | Game over.                           | the tide rolls back.             |
| phaseHint (opponent)                           | {name} is thinking…                  | {name} reads the tide…           |
| `GameStore.swift:56-65` bank button (default) | Bank                                 | Keep                             |
| bank button (steal variant)                    | Steal {name}'s tile                  | Take {name}'s shell              |
| `GameView.swift:402` roll button               | Roll / Roll Again                    | Roll On                          |
| `GameView.swift:280` bust headline             | bust.                                | the tide takes.                  |
| `GameView.swift:104-105` bust subline (greedy) | you had no coins and got greedy      | no coin in hand. try again.      |
| bust subline (rolled)                          | the roll gave you nothing            | the tide gave nothing. try again. |
| `GameView.swift:304` burned tile label         | tile burned                          | a shell drifts away              |
| `Scoreboard.swift:49` per-column total         | {n} tile / tiles                     | {n} pearls (or "0 shells" empty) |
| `Scoreboard.swift:83` steal flash              | stolen!                              | taken.                           |
| `CountingCeremony.swift:99` empty vault        | no safes claimed                     | 0 shells                         |
| `CountingCeremony.swift:21-29` winner          | You win. / It's a tie!               | you win. / a tie.                |
| `GameOverSheet.swift` (unused, kept in sync)   | game over. / tie at the top.         | the tide rolls back. / a tie.    |

Kept as-is (already calm or non-user-facing): `ActionBar` "game over",
"waiting…", `DiceStage` "dice ready", "locked".

The "shell yes" wordmark stays untouched on `SplashView` and `ChromeBar` — only
the wordmark keeps that energy; everything else is calm.

## 3. Pearl visual

`DesignSystem.swift`:

- New colors: `pearlHighlight` (cream center), `pearlCore` (mid amber),
  `pearlEdge` (deep amber rim), `pearlGlow` (outer halo).
- New view `Pearl(diameter:)` renders a radial gradient (cream → amber) with a
  diffuse `plusLighter` halo. No metallic hard highlight.
- `CoinPips` renamed to `PearlRow` (same call signature). All five callers
  updated: `VaultStack`, `SafesGrid`, `CountingCeremony.tileChip`,
  `GameView.burnedTileChip`. The end-ceremony big coin glyph now uses `Pearl`
  too (was `coinGlyph`, replaced with `pearlGlyph`).

`Color.gold` is kept — still used by gold dice faces, winner headline, and
sparkle effects (which are not pearls).

## 4. Shell-card tile geometry — Option A confirmed

Decided after browser mockup comparison (`/tmp/shell-stacking-options.html`).

- New `ShellCardShape: InsettableShape` in `DesignSystem.swift`: 5 scalloped
  crown bumps across the top, **straight parallel sides** (required for clean
  vertical stacking per `CLAUDE.md`), centered umbo nub at the bottom.
  Configurable crown / nub ratios.
- Applied wherever a tile is drawn:
  `VaultStack.safeView`, `SafesGrid.cellLayer`, `GameView.burnedTileChip`,
  `CountingCeremony.tileChip`, `Scoreboard.safePlaceholder`,
  `GameOverSheet.miniSafe`.
- Stacking direction in `VaultStack` is unchanged (newest on top, in front,
  5-px layer offset). With shells, each lower shell's 5-px peek below the top
  shell now reads as the umbo nub of the older shell rather than a bare bottom
  edge. Only the top (steal-target) shell renders the value + pearls — same as
  before.

## 5. Reward feedback — hook points + sound manifest

Wired vs. staged:

| Feel target                              | UI / sound trigger              | Wired? |
|------------------------------------------|---------------------------------|--------|
| Good outcome (sparkle + soft chime)      | `DiceStage.handlePick` → `GameSFX.playConfirm()` + `pickSparkleTrigger` | ✅ wired |
| Bank (warm low "tucked away" tone)       | `GameView.act` on vault-grow → `GameSFX.playBank()` + `VaultStack` sparkle | ✅ sound + sparkle wired; "tucked away." text **staged, not wired** (see below) |
| Bust (gentle wash / wave)                | `GameView.triggerBustFlash` → `GameSFX.playBust()` + full-screen flash | ✅ wired |
| Good-grab microcopy variants             | n/a                             | **strings staged, not wired** (see below) |

### Sound manifest

| Filename                                      | Pool size | Trigger                            | Intended mood                                              |
|-----------------------------------------------|-----------|------------------------------------|------------------------------------------------------------|
| `dice_picking.m4a` (+ `_2`)                   | 6         | each roll-anim frame, ~12/s        | soft pebble click; gentle pace, never percussive           |
| `dice_confirm.m4a`                            | 2         | `playConfirm()` on a die pick      | tiny chime / single bell, the "sparkle on the pearl" cue   |
| `outcome-success.m4a`                         | 2         | `playBank()` on a successful bank  | warm low "tucked away" tone; calmer than the pick chime    |
| `outcome-failure.m4a`                         | 2         | `playBust()` on bust               | gentle wash / wave; never a buzzer or descending stinger    |
| `farran_ez-minimal-piano-underscore-…mp3`     | n/a       | `HomeAudio` ambient loop           | unchanged. balearic piano underscore.                       |

All assets exist; no new asset files need to be commissioned for the wired
hooks to work. The user can audit each clip against the mood column above and
swap if any feels off-spec (esp. `outcome-success` — it should be a warmer,
lower tone than the pick chime to read distinct from "good-grab").

### Strings staged but not wired (deliberately out of scope)

These were listed in the spec but no UI element exists yet, and adding one is
feature-scope past "copy + visual-model + geometry only":

- **"tucked away."** — bank confirm banner. Hook point: `GameView.act` line 54
  (where `playBank()` already fires). Pattern to mirror: the bust overlay
  (`GameView` lines 250-317), but smaller / floating / warmer.
- **"nice." / "lovely." / "the tide gives."** — good-grab microcopy variants
  on a die pick. Hook point: `DiceStage.handlePick` line 268. Pattern: brief
  inline flash above the dice-stage sum.

If you want either wired, it's a follow-up of ~40 lines of SwiftUI each.

## 6. Files touched

- `ios/CHING/CHING/DesignSystem.swift` — pearl colors, `Pearl` + `PearlRow`,
  `ShellCardShape`.
- `ios/CHING/CHING/VaultStack.swift` — `ShellCardShape`, `PearlRow`.
- `ios/CHING/CHING/SafesGrid.swift` — header copy, `ShellCardShape`, `PearlRow`.
- `ios/CHING/CHING/GameStore.swift` — `bankActionLabel`, `phaseHint`.
- `ios/CHING/CHING/GameView.swift` — Roll button copy, bust headline + subline,
  burned-tile label, `burnedTileChip` shape + `PearlRow`.
- `ios/CHING/CHING/Scoreboard.swift` — score label, stolen flash, placeholder.
- `ios/CHING/CHING/CountingCeremony.swift` — empty-vault label, winner copy,
  `tileChip` shape, `coinGlyph` → `pearlGlyph`, `PearlRow`.
- `ios/CHING/CHING/SplashView.swift` — tagline.
- `ios/CHING/CHING/GameOverSheet.swift` — currently unused, updated for
  consistency in case it's re-wired later (`ShellCardShape`, calm copy).

## 7. Engine — explicit confirmation

**No engine changes.** No file under `src/` or `ios/CHINGEngine/` was touched.

- `npm test` — 107/107 pass.
- `xcodebuild … build` — succeeds.
- Tile values 21-36 → pearl counts 1/2/3/4: unchanged (engine `tileCoins`).
- Steal rule (exact match on rival's top shell): unchanged.
- Stacking rule (newest on top, top is steal target): unchanged.
- Burn-on-bust rule: unchanged.

## 8. Skipped / out of scope

- Terminal renderer (`src/cli.ts`, `src/render.ts`) and CLI README: unchanged.
  CLAUDE.md notes the terminal keeps the 80s/8-bit aesthetic separately. The
  theme refinement target was the iOS app's balearic vibe.
- `package.json` name `"ching"`, repo name, `~/.ching/session.json` paths:
  outside this pass; belongs to the broader `shell-yes-rebrand` work.
- No new string catalog / `Localizable.strings` introduced. Strings stay
  inline, matching the existing codebase convention.
