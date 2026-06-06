import SwiftUI
import CHINGEngine

struct GameOverSheet: View {
    let players: [Player]
    let scores: [Int]
    let onNewGame: () -> Void

    private struct Ranked {
        let id: String
        let score: Int
        let safes: [Int]
    }

    private var ranked: [Ranked] {
        zip(players, scores)
            .map { Ranked(id: $0.id, score: $1, safes: $0.tiles) }
            .sorted { $0.score > $1.score }
    }

    private var topScore: Int { ranked.first?.score ?? 0 }
    private var leaderCount: Int { ranked.filter { $0.score == topScore }.count }

    private var headline: String {
        if leaderCount == 1 {
            return "\(ranked.first!.id.capitalized) wins."
        }
        return "tie at the top."
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 40)

                Text("game over.")
                    .font(.avenir(34, weight: .ultraLight, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.ink)

                Text(headline)
                    .font(.avenir(18, weight: .demiBold))
                    .foregroundStyle(Color.coral)
                    .padding(.top, 8)

                Spacer()
                    .frame(height: 28)

                VStack(spacing: 12) {
                    ForEach(ranked.indices, id: \.self) { i in
                        rankedRow(ranked[i], isLeader: ranked[i].score == topScore)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button("New Game") { onNewGame() }
                    .stampButton()
                    .frame(maxWidth: 280)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private func rankedRow(_ r: Ranked, isLeader: Bool) -> some View {
        HStack(spacing: 14) {
            Text(r.id.capitalized)
                .font(.avenir(16, weight: .medium, italic: true))
                .foregroundStyle(isLeader ? Color.coral : Color.ink)
                .frame(width: 70, alignment: .leading)

            Text("\(r.score)")
                .font(.avenir(28, weight: isLeader ? .demiBold : .ultraLight))
                .foregroundStyle(Color.ink)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: -10) {
                ForEach(r.safes.suffix(4), id: \.self) { safe in
                    miniSafe(value: safe)
                }
                if r.safes.count > 4 {
                    Text("+\(r.safes.count - 4)")
                        .font(.avenir(10, weight: .medium, italic: true))
                        .foregroundStyle(Color.dimInk)
                        .padding(.leading, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isLeader ? Color.coral.opacity(0.18) : Color.white.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isLeader ? Color.coral.opacity(0.4) : Color.ink.opacity(0.15), lineWidth: 1)
        )
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
                        .strokeBorder(Color.ink, lineWidth: 1)
                )

            Text("\(value)")
                .font(.avenir(11, weight: .demiBold))
                .foregroundStyle(Color.ink)
        }
        .frame(width: 26, height: 28)
        .shadow(color: Color.ink.opacity(0.12), radius: 0, x: 0, y: 1)
    }
}
