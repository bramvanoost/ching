import SwiftUI
import CHINGEngine

struct Scoreboard: View {
    let players: [Player]
    let scores: [Int]
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(players.indices, id: \.self) { i in
                column(playerIndex: i)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func column(playerIndex i: Int) -> some View {
        let isActive = i == current
        VStack(spacing: 4) {
            Text(players[i].id.capitalized)
                .font(.avenir(11, weight: .medium, italic: true))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(isActive ? Color.coral : Color.dimInk)

            Text("\(scores[i])")
                .font(.avenir(28, weight: isActive ? .demiBold : .ultraLight))
                .foregroundStyle(Color.ink)
                .padding(.top, 1)

            if players[i].tiles.isEmpty {
                Text("empty")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .textCase(.lowercase)
                    .tracking(1)
                    .foregroundStyle(Color.dimInk.opacity(0.7))
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            } else {
                VaultStack(safes: players[i].tiles, activeSeat: isActive)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? Color.white.opacity(0.45) : Color.white.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isActive ? Color.coral.opacity(0.4) : Color.ink.opacity(0.15),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .shadow(color: isActive ? Color.coral.opacity(0.25) : .clear, radius: 12, x: 0, y: 0)
    }
}
