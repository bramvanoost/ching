import SwiftUI
import CHINGEngine

struct Scoreboard: View {
    let players: [Player]
    let scores: [Int]
    let current: Int
    var revealed: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            ForEach(players.indices, id: \.self) { i in
                column(playerIndex: i)
                    .frame(maxWidth: .infinity)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 24)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.78).delay(Double(i) * 0.12),
                        value: revealed
                    )
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
        VStack(spacing: 8) {
            Text(players[i].id.capitalized)
                .font(.avenir(14, weight: isActive ? .demiBold : .medium))
                .foregroundStyle(Color.ink)

            // Always reserve the vault area height so columns don't jump
            ZStack {
                if players[i].tiles.isEmpty {
                    safePlaceholder()
                } else {
                    VaultStack(safes: players[i].tiles, activeSeat: isActive)
                }
            }
            .frame(height: 54, alignment: .top)

            Text("\(safeCount) \(safeCount == 1 ? "tile" : "tiles")")
                .font(.avenir(10, weight: .medium, italic: true))
                .tracking(1)
                .foregroundStyle(Color.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 12)
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

    @ViewBuilder
    private func safePlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(
                Color.treasureInk.opacity(0.4),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )
            .frame(width: 38, height: 42)
    }
}
