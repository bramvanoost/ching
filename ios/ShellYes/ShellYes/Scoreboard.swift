import SwiftUI
import CHINGEngine

struct Scoreboard: View {
    let players: [Player]
    let scores: [Int]
    let current: Int
    var revealed: Bool = true
    var stolenFrom: Int? = nil

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
        let isStolen = stolenFrom == i
        let pearlCount = scores[i]
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

            if players[i].tiles.isEmpty {
                Text("0 shells")
                    .font(.avenir(10, weight: .medium, italic: true))
                    .tracking(1)
                    .foregroundStyle(Color.ink.opacity(0.55))
            } else {
                Text("\(pearlCount) pearls")
                    .font(.avenir(10, weight: .medium, italic: true))
                    .tracking(1)
                    .foregroundStyle(Color.ink.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isStolen ? Color.coral.opacity(0.45) :
                    isActive ? Color.white.opacity(0.45) :
                    Color.white.opacity(0.18)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isStolen ? Color.coral :
                    isActive ? Color.coral.opacity(0.4) :
                    Color.ink.opacity(0.15),
                    lineWidth: isStolen ? 2.5 : (isActive ? 1.5 : 1)
                )
        )
        .shadow(
            color: isStolen ? Color.coral.opacity(0.75) :
                   isActive ? Color.coral.opacity(0.25) : .clear,
            radius: isStolen ? 18 : 12,
            x: 0, y: 0
        )
        .scaleEffect(isStolen ? 1.04 : 1.0)
        .overlay(alignment: .top) {
            if isStolen {
                Text("taken.")
                    .font(.avenir(13, weight: .demiBold, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.coral)
                    .shadow(color: Color.paper.opacity(0.8), radius: 3, x: 0, y: 0)
                    .offset(y: -16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isStolen)
    }

    @ViewBuilder
    private func safePlaceholder() -> some View {
        ShellCardShape()
            .strokeBorder(
                Color.treasureInk.opacity(0.4),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )
            .frame(width: 38, height: 42)
    }
}
