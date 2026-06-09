# Shell Yes, audio: pentatonic dice pickup (parked)

Date: 2026-06-09
Status: parked, not started

## The idea

Monument Valley plays successive notes of a pentatonic scale in response to interaction beats (rotate N clicks, hear N rising notes). The natural Shell Yes analogue: as the player picks dice and sets them aside, each pick advances the ladder by one note, so a hot turn becomes a little melodic phrase that resolves into the ka-ching on bank.

Mapping sketch:
- Quantity drives pitch ascent (1st pick = root, 2nd = 2nd of the scale, etc).
- Ladder resets per turn so each turn starts at the root.
- Value (1 to 5) could later modulate velocity or octave, but start with quantity-only.
- Bust kills the phrase mid-climb (no resolution), bank completes it (resolves into ka-ching).
- Soft, fast-decaying instrument so notes do not pile up on long turns.

## Why not now

Lots of other UX polish in-flight (claim pop, tally redesign, last-shell modal, icon). Audio system work would compete with that for attention. Parking until visual layer settles.

## Technical recommendation when revived

Samples, not synthesis. iOS can synth via `AVAudioEngine`'s source node but it sounds sterile without real DSP work.

Pitch-shift one tonal sample across the scale via `AVAudioUnitSampler`:
- Hand it one .wav plus a base note.
- It auto-pitches across the keyboard.
- Within roughly an octave the timbre stays believable.
- Past that it starts sounding like a chipmunk, so cap the ladder at 5 to 6 notes.

The existing sample pack is tonal, so one of its existing samples can likely serve as the base note. No new asset required to prototype. If a specific in-pack sample turns out unsuitable, adding one new tonal asset (kalimba pluck, glass ping, soft bell at a known pitch) is the minimal expansion.

## Next step if revived

1. Pick a base sample from the current pack and confirm its fundamental pitch.
2. Wire `AVAudioUnitSampler` with that sample plus base note.
3. Prototype the 5-note pentatonic ladder on dice pickup only (skip value mapping, skip bank/bust resolution).
4. Play 10 turns, decide whether the rhythm lands before adding axes.

## Open questions

- Does the ladder feel rewarding or noisy when the player picks a lot of low-value dice?
- Should the AI's picks also play notes, or stay silent so the audio is a player-only reward?
- Pentatonic minor or major? Minor sits better against the dusk/coral palette but major resolves more like a "win."

## Related memory

- `ching-pop-over-restraint.md` (lead bolder), favours doing this rather than leaving the dice silent.
- `telemetry-update-checklist.md`, if shipped, decide whether to log a per-turn "melodic ladder completed" or skip telemetry on audio events.
