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
        let safeCount = players[i].tiles.count
        VStack(spacing: 6) {
            Text(players[i].id.capitalized)
                .font(.avenir(13, weight: isActive ? .demiBold : .medium, italic: true))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(isActive ? Color.coral : Color.dimInk)

            if players[i].tiles.isEmpty {
                Text("empty")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .textCase(.lowercase)
                    .tracking(1)
                    .foregroundStyle(Color.dimInk.opacity(0.7))
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            } else {
                VaultStack(safes: players[i].tiles, activeSeat: isActive)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                Text("\(safeCount) \(safeCount == 1 ? "safe" : "safes")")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .tracking(1)
                    .foregroundStyle(Color.dimInk.opacity(0.8))
                    .padding(.bottom, 6)
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
