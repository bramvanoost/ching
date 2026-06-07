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
                        .foregroundStyle(Color.ink.opacity(0.7))
                        .padding(.horizontal, 24)
                }

                if let shell = shellNumber {
                    shellChip(value: shell, drifting: false)
                        .padding(.top, 4)
                } else if case .bust(_, let burned) = event, let burned {
                    shellChip(value: burned, drifting: true)
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
                    .foregroundStyle(Color.ink.opacity(0.45))
                    .padding(.top, 6)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardFill)
            )
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
        case .took(let actor, let shell):
            if actor.lowercased() == "you" {
                return "Nice, you claimed shell \(shell)!"
            }
            return "\(actor) claimed a shell!"
        case .stole(let actor, let victim, let shell):
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
        return Color.ink
    }

    private enum Tone { case positive, negative, neutral }

    /// Player-perspective tone. Positive = good for you (you claimed, AI
    /// busted). Negative = bad for you (AI took your shell). Neutral = the
    /// event doesn't directly involve you.
    private var tone: Tone {
        switch event {
        case .took(let actor, _):
            return actor.lowercased() == "you" ? .positive : .neutral
        case .stole(let actor, let victim, _):
            if actor.lowercased() == "you" { return .positive }
            if victim.lowercased() == "you" { return .negative }
            return .neutral
        case .bust(let actor, _):
            return actor.lowercased() == "you" ? .negative : .positive
        }
    }

    private var cardFill: Color {
        // Positive and neutral both sit on the default paper card. Only
        // negative-for-you events (a rival took your shell) get the rose
        // wash — green clashed with the warm palette, so it was reverted.
        switch tone {
        case .negative: return Color.bannerNegative
        case .positive, .neutral: return Color.paper
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
        case .took:
            return nil
        case .stole:
            return nil
        case .bust(_, let burned):
            if let burned {
                return "shell \(burned) drifts away."
            }
            return "a shell drifts away."
        }
    }

    private var shellNumber: Int? {
        switch event {
        case .took(_, let shell), .stole(_, _, let shell):
            return shell
        case .bust:
            return nil
        }
    }

    @ViewBuilder
    private func shellChip(value: Int, drifting: Bool) -> some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            ShellCardShape()
                .fill(
                    drifting
                        ? LinearGradient(
                            colors: [Color.ink.opacity(0.12), Color.ink.opacity(0.18)],
                            startPoint: .top, endPoint: .bottom
                          )
                        : LinearGradient(
                            colors: [Color.safePeachLight, Color.safePeachDark],
                            startPoint: .top, endPoint: .bottom
                          )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(
                            drifting ? Color.treasureInk.opacity(0.45) : Color.treasureInk,
                            style: StrokeStyle(lineWidth: 2, dash: drifting ? [3, 3] : [])
                        )
                )
                .shadow(color: Color.treasureInk.opacity(drifting ? 0 : 0.25), radius: 0, x: 0, y: 4)
                .shadow(color: Color.coralDark.opacity(drifting ? 0.35 : 0.2), radius: 14, x: 0, y: 0)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(28, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk.opacity(drifting ? 0.55 : 1.0))
                PearlRow(count: coins, diameter: 7, spacing: 3)
                    .opacity(drifting ? 0.35 : 1.0)
            }
        }
        .frame(width: 68, height: 84)
        .opacity(drifting ? 0.85 : 1.0)
    }
}
