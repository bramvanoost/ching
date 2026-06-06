import SwiftUI
import CHINGEngine

struct Scoreboard: View {
    let players: [Player]
    let scores: [Int]
    let current: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(players.indices, id: \.self) { i in
                column(playerIndex: i)
                    .frame(maxWidth: .infinity)
                if i < players.count - 1 {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 1)
                }
            }
        }
        .overlay(
            VStack(spacing: 0) {
                Rectangle().fill(Color.ink).frame(height: 1.5)
                Spacer()
                Rectangle().fill(Color.ink).frame(height: 1.5)
            }
        )
    }

    @ViewBuilder
    private func column(playerIndex i: Int) -> some View {
        let isActive = i == current
        VStack(spacing: 6) {
            Text(players[i].id.capitalized)
                .font(.cochinItalic(10))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(isActive ? Color.paper.opacity(0.7) : Color.dimInk)
                .padding(.top, 12)

            Text("\(scores[i])")
                .font(.cochin(36))
                .foregroundStyle(isActive ? Color.paper : Color.ink)

            VaultStack(safes: players[i].tiles, activeSeat: isActive)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(isActive ? Color.ink : Color.paper)
    }
}
