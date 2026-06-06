import SwiftUI
import CHINGEngine

struct CountingCeremony: View {
    let players: [Player]
    let scores: [Int]
    let onNewGame: () -> Void

    @SwiftUI.State private var revealedPlayer: Int = -1   // index currently or last animated
    @SwiftUI.State private var tickedTotals: [Int] = []
    @SwiftUI.State private var winnerRevealed: Bool = false
    @SwiftUI.State private var showNewGame: Bool = false

    private var winnerIndices: [Int] {
        guard let top = scores.max() else { return [] }
        return scores.enumerated().compactMap { idx, s in s == top ? idx : nil }
    }

    private var winnerHeadline: String {
        if winnerIndices.count == 1 {
            let idx = winnerIndices[0]
            if idx == GameStore.humanSeat {
                return "You win."
            }
            return "\(players[idx].id.capitalized) wins."
        }
        return "Tie at the top."
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer().frame(height: 30)

                Text("counting…")
                    .font(.avenir(28, weight: .ultraLight, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.ink)
                    .opacity(winnerRevealed ? 0 : 1)
                    .animation(.easeOut(duration: 0.4), value: winnerRevealed)

                if winnerRevealed {
                    ZStack {
                        SparkleField(count: 48, startRadius: 80, spread: 150, duration: 1.6)
                            .frame(width: 360, height: 100)
                            .offset(y: 0)
                        Text(winnerHeadline)
                            .font(.avenir(30, weight: .demiBold, italic: true))
                            .tracking(2)
                            .foregroundStyle(Color.gold)
                            .shadow(color: Color.gold.opacity(0.6), radius: 14, x: 0, y: 0)
                            .shadow(color: Color.ink.opacity(0.4), radius: 0, x: 0, y: 1)
                    }
                    .padding(.top, -38)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Spacer().frame(height: 28)

                VStack(spacing: 14) {
                    ForEach(players.indices, id: \.self) { i in
                        playerRow(i)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                if showNewGame {
                    Button("New Game") { onNewGame() }
                        .stampButton()
                        .frame(maxWidth: 280)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .task {
            await runCeremony()
        }
    }

    @ViewBuilder
    private func playerRow(_ i: Int) -> some View {
        let isRevealed = revealedPlayer >= i
        let isCurrentlyCounting = revealedPlayer == i && !winnerRevealed
        let isWinner = winnerRevealed && winnerIndices.contains(i)
        let displayedTotal = tickedTotals.indices.contains(i) ? tickedTotals[i] : 0

        ZStack {
            HStack(spacing: 14) {
                Text(players[i].id.capitalized)
                    .font(.avenir(16, weight: isWinner ? .demiBold : .medium, italic: true))
                    .foregroundStyle(Color.ink)
                    .frame(width: 72, alignment: .leading)

                Spacer()

                // Mini vault row
                HStack(spacing: -8) {
                    ForEach(players[i].tiles.suffix(5), id: \.self) { safe in
                        miniSafe(value: safe)
                    }
                    if players[i].tiles.count > 5 {
                        Text("+\(players[i].tiles.count - 5)")
                            .font(.avenir(10, weight: .medium, italic: true))
                            .foregroundStyle(Color.dimInk)
                            .padding(.leading, 14)
                    }
                }

                Spacer()

                // Coin total — large during ceremony
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(displayedTotal)")
                        .font(.avenir(30, weight: isWinner ? .demiBold : .ultraLight))
                        .foregroundStyle(Color.ink)
                    Text("c")
                        .font(.avenir(13, weight: .medium, italic: true))
                        .foregroundStyle(Color.gold)
                        .padding(.bottom, 5)
                }
                .opacity(isRevealed ? 1.0 : 0.25)
                .frame(width: 72, alignment: .trailing)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isWinner ? Color.gold.opacity(0.25) : Color.white.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isWinner ? Color.gold.opacity(0.65) : Color.ink.opacity(0.15),
                        lineWidth: isWinner ? 1.5 : 1
                    )
            )
            .shadow(color: isCurrentlyCounting ? Color.gold.opacity(0.4) : .clear, radius: 12, x: 0, y: 0)
            .shadow(color: isWinner ? Color.gold.opacity(0.55) : .clear, radius: 18, x: 0, y: 0)
            .scaleEffect(isWinner ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.35), value: isWinner)

            if isWinner {
                SparkleField(count: 36, startRadius: 110, spread: 120, duration: 1.4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func miniSafe(value: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.treasureInk, lineWidth: 1)
                )
            Text("\(value)")
                .font(.avenir(10, weight: .demiBold))
                .foregroundStyle(Color.treasureInk)
        }
        .frame(width: 22, height: 26)
        .shadow(color: Color.treasureInk.opacity(0.12), radius: 0, x: 0, y: 1)
    }

    private func runCeremony() async {
        // Initialize tickedTotals as zeros for each player.
        tickedTotals = Array(repeating: 0, count: players.count)

        // Brief moment to let "counting…" settle in.
        try? await Task.sleep(nanoseconds: 600_000_000)

        for i in players.indices {
            revealedPlayer = i
            let target = scores[i]
            if target == 0 {
                // Just pause to acknowledge them, then move on.
                try? await Task.sleep(nanoseconds: 350_000_000)
            } else {
                // Tick from 0 to target. Per-step delay scales so the whole
                // count takes ~1.0–1.4s regardless of size.
                let stepNs: UInt64 = UInt64(max(40_000_000, min(140_000_000, 1_200_000_000 / UInt64(max(1, target)))))
                for v in 1...target {
                    tickedTotals[i] = v
                    try? await Task.sleep(nanoseconds: stepNs)
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        // All players counted — pause, then reveal winner.
        try? await Task.sleep(nanoseconds: 400_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            winnerRevealed = true
        }

        // Pause for impact, then show New Game.
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeOut(duration: 0.4)) {
            showNewGame = true
        }
    }
}
