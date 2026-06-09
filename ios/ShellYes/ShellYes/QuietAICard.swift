import SwiftUI

/// Calm placeholder that takes the dice stage's vertical slot when
/// `settings.quietAITurns` is on and an AI seat is playing. Shows the
/// active AI's name as "{name} is making waves" with a layered sine-
/// wave animation that scrolls for the full `GameStore.quietTurnDwell`
/// before the outcome banner punches in.
///
/// Sized to match `DiceStage.frame(height: 158)` so swapping in / out
/// doesn't reflow the rest of the column (shells grid above, action
/// bar below).
struct QuietAICard: View {
    let name: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Waves crest from a flat line into full amplitude as they
    /// arrive — the metaphor's hero moment. `amplitudeScale` drives
    /// each WaveLine's amplitude inside the TimelineView so SwiftUI's
    /// animation system interpolates it frame-by-frame.
    @SwiftUI.State private var amplitudeScale: CGFloat = 0
    @SwiftUI.State private var wavesEntered: Bool = false
    @SwiftUI.State private var titleEntered: Bool = false
    @SwiftUI.State private var taglineEntered: Bool = false

    // ease-out-quint — refined natural deceleration; no bounce,
    // doesn't draw attention to itself. The animate skill's pick over
    // SwiftUI's default `.easeOut`, which feels generic.
    private static let easeOutQuint = SwiftUI.Animation.timingCurve(
        0.22, 1, 0.36, 1, duration: 0.65
    )

    private var titleText: String { "\(name) is making waves" }

    private var wavyTitle: some View {
        let chars = Array(titleText)
        return TimelineView(.animation) { context in
            let phase = CGFloat(context.date.timeIntervalSinceReferenceDate * 1.4)
            HStack(spacing: 0.3) {
                ForEach(Array(chars.enumerated()), id: \.offset) { idx, ch in
                    wavyChar(ch, index: idx, phase: phase)
                }
            }
        }
    }

    private func wavyChar(_ ch: Character, index: Int, phase: CGFloat) -> some View {
        let yOffset = sin(CGFloat(index) * 0.5 - phase) * 2.6 * amplitudeScale
        return Text(String(ch))
            .font(.avenir(15, weight: .medium, italic: true))
            .foregroundStyle(Color.ink.opacity(0.8))
            .offset(y: yOffset)
    }

    var body: some View {
        VStack(spacing: 18) {
            // Title text broken into per-character Texts so each
            // glyph can ride its own sine displacement — the line
            // itself becomes a wave that runs left-to-right, echoing
            // the "making waves" copy. Continuous (TimelineView wall
            // time) and amplitude-scaled so the wave swells up with
            // the same `amplitudeScale` driver the WaveLines use,
            // unifying the entrance. The per-char view is extracted
            // to keep the body's type-checker happy.
            wavyTitle
                .fixedSize()
                .opacity(titleEntered ? 1 : 0)
                .offset(y: titleEntered ? 0 : 12)
                .scaleEffect(titleEntered ? 1 : 0.97, anchor: .center)

            // Three sine layers at slightly different speeds /
            // wavelengths / amplitudes. The eye reads the stack as
            // chop on an open surface rather than one mechanical
            // squiggle — and the parallax fakes depth without a
            // gradient or fill. TimelineView(.animation) drives the
            // phase off wall time so animation continues even when
            // SwiftUI elides redraws.
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t)
                ZStack {
                    WaveLine(wavelength: 64, amplitude: 5 * amplitudeScale, phase: phase * 0.9)
                        .stroke(Color.ink.opacity(0.18), lineWidth: 1.4)
                    WaveLine(wavelength: 44, amplitude: 6 * amplitudeScale, phase: -phase * 1.3 + 1.1)
                        .stroke(Color.ink.opacity(0.32), lineWidth: 1.6)
                    WaveLine(wavelength: 30, amplitude: 4 * amplitudeScale, phase: phase * 1.7 + 2.4)
                        .stroke(Color.ink.opacity(0.55), lineWidth: 1.6)
                }
            }
            .frame(height: 36)
            .padding(.horizontal, 32)
            .opacity(wavesEntered ? 1 : 0)
            .offset(y: wavesEntered ? 0 : 16)

            Text("rolling under the swell")
                .font(.avenir(11, weight: .medium, italic: true))
                .tracking(2)
                .textCase(.lowercase)
                .foregroundStyle(Color.ink.opacity(0.42))
                .opacity(taglineEntered ? 1 : 0)
                .offset(y: taglineEntered ? 0 : 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 158)
        .padding(.horizontal, 20)
        .onAppear(perform: animateIn)
    }

    private func animateIn() {
        // Reduce-motion: snap everything into place. No rise, no
        // amplitude swell, no stagger. Respect the accessibility
        // setting before doing any motion design.
        guard !reduceMotion else {
            amplitudeScale = 1
            wavesEntered = true
            titleEntered = true
            taglineEntered = true
            return
        }
        // Staggered entrance: waves crest first (the surface
        // establishes), name surfaces just behind, tagline drifts in
        // last as a quiet caption. Total settled by ~0.75s, leaving
        // ~1.25s of breath inside the 2.0s dwell.
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.75)) {
            amplitudeScale = 1
            wavesEntered = true
        }
        withAnimation(Self.easeOutQuint.delay(0.12)) {
            titleEntered = true
        }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.45).delay(0.30)) {
            taglineEntered = true
        }
    }
}
