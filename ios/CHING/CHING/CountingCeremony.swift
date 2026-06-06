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
    @SwiftUI.State private var sparkleWave: Int = 0

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
                Spacer().frame(height: 26)

                Text("counting…")
                    .font(.avenir(28, weight: .ultraLight, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.ink)
                    .opacity(winnerRevealed ? 0 : 1)
                    .animation(.easeOut(duration: 0.4), value: winnerRevealed)

                if winnerRevealed {
                    Text(winnerHeadline)
                        .font(.avenir(30, weight: .demiBold, italic: true))
                        .tracking(2)
                        .foregroundStyle(Color.gold)
                        .shadow(color: Color.gold.opacity(0.6), radius: 14, x: 0, y: 0)
                        .shadow(color: Color.ink.opacity(0.4), radius: 0, x: 0, y: 1)
                        .padding(.top, -34)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Spacer().frame(height: 22)

                VStack(spacing: 14) {
                    ForEach(players.indices, id: \.self) { i in
                        playerCard(i)
                    }
                }
                .padding(.horizontal, 20)

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
    private func playerCard(_ i: Int) -> some View {
        let isRevealed = revealedPlayer >= i
        let isCurrentlyCounting = revealedPlayer == i && !winnerRevealed
        let isWinner = winnerRevealed && winnerIndices.contains(i)
        let displayedTotal = tickedTotals.indices.contains(i) ? tickedTotals[i] : 0

        VStack(spacing: 12) {
            // Name
            Text(players[i].id.capitalized)
                .font(.avenir(15, weight: isWinner ? .demiBold : .medium, italic: true))
                .foregroundStyle(Color.ink)
                .tracking(1)

            // Tile row — each tile shows its number + the coins it's worth.
            ZStack {
                if players[i].tiles.isEmpty {
                    Text("no safes claimed")
                        .font(.avenir(11, weight: .medium, italic: true))
                        .tracking(1.5)
                        .textCase(.lowercase)
                        .foregroundStyle(Color.ink.opacity(0.45))
                } else {
                    HStack(spacing: -4) {
                        ForEach(players[i].tiles, id: \.self) { tile in
                            tileChip(value: tile)
                        }
                    }
                }
            }
            .frame(height: 44)

            // Big coin total + same-sized coin, side by side.
            HStack(alignment: .center, spacing: 10) {
                Text("\(displayedTotal)")
                    .font(.avenir(48, weight: .demiBold))
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                coinGlyph(size: 48)
                    .shadow(color: Color.treasureInk.opacity(0.2), radius: 0, x: 0, y: 2)
            }
            .opacity(isRevealed ? 1.0 : 0.25)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isWinner ? Color.gold.opacity(0.28) : Color.white.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isWinner ? Color.gold.opacity(0.75) : Color.ink.opacity(0.15),
                    lineWidth: isWinner ? 1.75 : 1
                )
        )
        .shadow(color: isCurrentlyCounting ? Color.gold.opacity(0.4) : .clear, radius: 12, x: 0, y: 0)
        .shadow(color: isWinner ? Color.gold.opacity(0.55) : .clear, radius: 22, x: 0, y: 0)
        .scaleEffect(isWinner ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.35), value: isWinner)
        .overlay {
            if isWinner {
                EdgeSparkleField(count: 90, inset: 2, spread: 22, duration: 1.5)
                    .id(sparkleWave)
            }
        }
    }

    @ViewBuilder
    private func tileChip(value: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.treasureInk, lineWidth: 1.25)
                )
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.avenir(12, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                CoinPips(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
            }
        }
        .frame(width: 30, height: 40)
        .shadow(color: Color.treasureInk.opacity(0.12), radius: 0, x: 0, y: 1)
    }

    @ViewBuilder
    private func coinGlyph(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.coinGoldLight, Color.gold],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.treasureInk, lineWidth: 2)
                )
            Circle()
                .strokeBorder(Color.coinGoldLight.opacity(0.7), lineWidth: 1.5)
                .padding(size * 0.13)
        }
        .frame(width: size, height: size)
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

        // Keep the winner card ringed in sparkles while the celebration is up.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            sparkleWave += 1
        }
    }
}
