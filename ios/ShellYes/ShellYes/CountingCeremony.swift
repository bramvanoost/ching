import SwiftUI
import ShellYesEngine

struct CountingCeremony: View {
    let players: [Player]
    let scores: [Int]
    let onNewGame: () -> Void

    @SwiftUI.State private var revealedPlayer: Int = -1   // index currently or last animated
    @SwiftUI.State private var tickedTotals: [Int] = []
    @SwiftUI.State private var winnerRevealed: Bool = false
    @SwiftUI.State private var showNewGame: Bool = false
    @SwiftUI.State private var sparkleWave: Int = 0
    @SwiftUI.State private var humanWinHeadlineSparkle: Int = 0

    private var winnerIndices: [Int] {
        guard let top = scores.max() else { return [] }
        return scores.enumerated().compactMap { idx, s in s == top ? idx : nil }
    }

    private var winnerHeadline: String {
        if winnerIndices.count == 1 {
            let idx = winnerIndices[0]
            if idx == GameStore.humanSeat {
                return "you win."
            }
            return "\(players[idx].id.capitalized.lowercased()) wins."
        }
        return "a tie."
    }

    private var isHumanWin: Bool {
        winnerIndices.count == 1 && winnerIndices[0] == GameStore.humanSeat
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
                    WinHeadline(text: winnerHeadline, festive: isHumanWin)
                        .padding(.top, -34)
                        .overlay {
                            if isHumanWin {
                                SparkleField(count: 44, startRadius: 18, spread: 95, duration: 1.4)
                                    .id(humanWinHeadlineSparkle)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                Spacer().frame(height: winnerRevealed ? 30 : 22)

                VStack(spacing: winnerRevealed ? 28 : 14) {
                    ForEach(players.indices, id: \.self) { i in
                        playerCard(i)
                    }
                }
                .padding(.horizontal, 20)
                .animation(.easeOut(duration: 0.5), value: winnerRevealed)

                Spacer()

                if showNewGame {
                    Button("New Game") { onNewGame() }
                        .stampButton(primary: true, invite: true)
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
                    Text("0 shells")
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

            // Big coin total + same-sized coin, side by side. The coin sits
            // a bit higher than the geometric center so it lines up with the
            // visible cap height of the italic digits.
            HStack(alignment: .center, spacing: 10) {
                Text("\(displayedTotal)")
                    .font(.avenir(48, weight: .demiBold))
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                pearlGlyph(size: 48)
                    .shadow(color: Color.pearlEdge.opacity(0.35), radius: 0, x: 0, y: 2)
                    .offset(y: -2)
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
                // Cards get extra row spacing on winner-reveal (see VStack
                // above), so the edge sparkles can actually fly outward
                // without crashing into the neighbour rows. Spread is
                // tuned to land inside that breathing room.
                EdgeSparkleField(count: 130, inset: 0, spread: 80, duration: 1.1)
                    .id(sparkleWave)
                // Radial inner burst — fills the card body so the
                // sparkles read as bursting FROM the card, not just
                // ringing its border.
                SparkleField(count: 36, startRadius: 14, spread: 60, duration: 1.3)
                    .id(sparkleWave)
            }
        }
    }

    @ViewBuilder
    private func tileChip(value: Int) -> some View {
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
                        .strokeBorder(Color.treasureInk, lineWidth: 1.25)
                )
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.avenir(12, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
            }
        }
        .frame(width: 30, height: 40)
        .shadow(color: Color.treasureInk.opacity(0.12), radius: 0, x: 0, y: 1)
    }

    @ViewBuilder
    private func pearlGlyph(size: CGFloat) -> some View {
        Pearl(diameter: size)
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
        // Headline sparkles run on a slightly offset cadence so the screen
        // doesn't pulse in a single beat.
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_100_000_000)
                humanWinHeadlineSparkle += 1
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            sparkleWave += 1
        }
    }
}

/// Winner headline. For the human win we go bigger and animate each glyph
/// in with a small bounce, then keep a gentle gold shimmer running so the
/// line doesn't sit static while the player reads it.
private struct WinHeadline: View {
    let text: String
    let festive: Bool

    @SwiftUI.State private var entered: Bool = false
    @SwiftUI.State private var shimmer: Bool = false
    @SwiftUI.State private var lift: Bool = false

    var body: some View {
        if festive {
            festiveBody
        } else {
            Text(text)
                .font(.avenir(30, weight: .demiBold, italic: true))
                .tracking(2)
                .foregroundStyle(Color.gold)
                .shadow(color: Color.gold.opacity(0.6), radius: 14, x: 0, y: 0)
                .shadow(color: Color.ink.opacity(0.4), radius: 0, x: 0, y: 1)
        }
    }

    private var festiveBody: some View {
        let chars = Array(text)
        return HStack(spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { idx, ch in
                Text(String(ch))
                    .font(.avenir(40, weight: .bold, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.gold)
                    .shadow(
                        color: Color.coinGoldLight.opacity(shimmer ? 0.95 : 0.55),
                        radius: shimmer ? 22 : 12,
                        x: 0, y: 0
                    )
                    .shadow(color: Color.gold.opacity(0.55), radius: 4, x: 0, y: 0)
                    .shadow(color: Color.ink.opacity(0.45), radius: 0, x: 0, y: 1)
                    .scaleEffect(entered ? 1 : 0.25)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? (lift ? -2 : 0) : 22)
                    .rotationEffect(.degrees(entered ? 0 : -8))
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.5)
                            .delay(0.05 * Double(idx)),
                        value: entered
                    )
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                            .delay(0.08 * Double(idx)),
                        value: lift
                    )
            }
        }
        .onAppear {
            entered = true
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                shimmer = true
            }
            // Stagger the breath so each letter rides a slightly different
            // wave — reads as continuous celebration, not a metronome.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                lift = true
            }
        }
    }
}
