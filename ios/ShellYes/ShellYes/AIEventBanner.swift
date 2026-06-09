import SwiftUI

struct AIEventBanner: View {
    let event: GameStore.AIEvent
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.ink.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(titleLine)
                    .font(.avenir(24, weight: .demiBold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(titleColor)
                    .padding(.horizontal, 18)

                if let subtitle = subtitleLine {
                    Text(subtitle)
                        .font(.avenir(14, weight: .medium, italic: true))
                        .tracking(2)
                        .textCase(.lowercase)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(subtitleColor)
                        .padding(.horizontal, 24)
                }

                if let shell = shellNumber {
                    ShellChip(value: shell, drifting: false, celebrate: tone == .positive)
                        .padding(.top, 4)
                } else if case .bust(_, let burned) = event, let burned {
                    ShellChip(value: burned, drifting: true, celebrate: false)
                        .padding(.top, 4)
                } else {
                    Image(systemName: "wind")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.coralDark)
                        .padding(.top, 4)
                }

                Text("tap to continue")
                    .font(.avenir(11, weight: .demiBold, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(tapHintColor)
                    .padding(.top, 6)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 320)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(cardStroke, lineWidth: tone == .negative ? 1.5 : 1)
            )
            .shadow(color: Color.ink.opacity(0.35), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var titleLine: String {
        switch event {
        case .took(let actor, let shell, let isFinal):
            if isFinal {
                if actor.lowercased() == "you" {
                    return "You claimed the last shell."
                }
                return "\(actor) claimed the last shell."
            }
            if actor.lowercased() == "you" {
                return "Nice, you claimed shell \(shell)!"
            }
            return "\(actor) claimed a shell!"
        case .stole(let actor, let victim, let shell, let isFinal):
            if isFinal {
                if actor.lowercased() == "you" {
                    return "You took \(victim)'s last shell."
                }
                if victim.lowercased() == "you" {
                    return "\(actor) took your last shell."
                }
                return "\(actor) took \(victim)'s last shell."
            }
            if actor.lowercased() == "you" {
                return "Nice, you took \(victim)'s shell \(shell)!"
            }
            if victim.lowercased() == "you" {
                return "\(actor) casually took your shell!"
            }
            return "\(actor) casually took \(victim)'s shell!"
        case .bust(let actor, _):
            return "\(actor) went bust"
        }
    }

    private var titleColor: Color {
        return tone == .negative ? Color.stampText : Color.ink
    }

    private var subtitleColor: Color {
        return tone == .negative ? Color.stampText.opacity(0.85) : Color.ink.opacity(0.7)
    }

    private var tapHintColor: Color {
        return tone == .negative ? Color.stampText.opacity(0.7) : Color.ink.opacity(0.45)
    }

    private enum Tone { case positive, negative, neutral }

    /// Player-perspective tone. Positive = good for you (you claimed, AI
    /// busted). Negative = bad for you (AI took your shell). Neutral = the
    /// event doesn't directly involve you.
    private var tone: Tone {
        switch event {
        case .took(let actor, _, _):
            return actor.lowercased() == "you" ? .positive : .neutral
        case .stole(let actor, let victim, _, _):
            if actor.lowercased() == "you" { return .positive }
            if victim.lowercased() == "you" { return .negative }
            return .neutral
        case .bust(let actor, _):
            return actor.lowercased() == "you" ? .negative : .positive
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch tone {
        case .negative:
            // Deeper coral-to-crimson gradient — cream text reads cleanly
            // against this where it didn't against the lighter rose.
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.coralDark, Color.bannerNegativeAccent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .positive, .neutral:
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.paper)
        }
    }

    private var cardStroke: Color {
        switch tone {
        case .negative: return Color.bannerNegativeAccent
        case .positive, .neutral: return Color.ink.opacity(0.18)
        }
    }

    private var subtitleLine: String? {
        switch event {
        case .took(_, _, let isFinal), .stole(_, _, _, let isFinal):
            // The final-shell banner closes the game and dissolves
            // into the tally — borrow the engine's game-over hint so
            // the language of the moment is consistent.
            return isFinal ? "the tide rolls back." : nil
        case .bust(_, let burned):
            if let burned {
                return "shell \(burned) drifts away."
            }
            return "a shell drifts away."
        }
    }

    private var shellNumber: Int? {
        switch event {
        case .took(_, let shell, _), .stole(_, _, let shell, _):
            return shell
        case .bust:
            return nil
        }
    }

}

/// Shell card chip shown inside the AI event banner. Owns its own pop
/// state so the shell springs in when the modal appears, distinct from
/// the modal's calmer fade-and-scale entrance.
private struct ShellChip: View {
    let value: Int
    let drifting: Bool
    let celebrate: Bool

    @SwiftUI.State private var popScale: CGFloat = 0.4

    var body: some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(
                            // Dashed stroke is the only "drifting away" cue
                            // we lean on now — the fill stays peach so the
                            // shell still reads as readable.
                            drifting ? Color.treasureInk.opacity(0.8) : Color.treasureInk,
                            style: StrokeStyle(lineWidth: 2, dash: drifting ? [3, 3] : [])
                        )
                )
                .shadow(color: Color.treasureInk.opacity(drifting ? 0.15 : 0.25), radius: 0, x: 0, y: 4)
                .shadow(color: Color.coralDark.opacity(0.2), radius: 14, x: 0, y: 0)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(28, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: coins, diameter: 7, spacing: 3)
            }
        }
        .frame(width: 68, height: 84)
        .opacity(drifting ? 0.85 : 1.0)
        // Rays of light render in `.background`, not as a sibling in
        // the ZStack: a sibling with its own larger frame would force
        // the ZStack — and ShellCardShape inside it — to that size.
        // Background sits behind the chip, so the portions of the
        // rays underneath the silhouette are hidden and only the
        // outer rays radiate beyond the shell.
        .background {
            if celebrate {
                LightRays()
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(popScale)
        .onAppear {
            // Snappier spring pop: short response so the chip arrives
            // fast, low damping for a visible overshoot past 1.0 before
            // settling. Starts at 0.4 so the growth itself is obvious.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) {
                popScale = 1.0
            }
        }
    }
}

