import SwiftUI

struct SafesGrid: View {
    let availableSafes: [Int]
    let remainingCount: Int

    private let allSafes: [Int] = Array(21...36)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("\(remainingCount)")
                    .font(.avenir(18, weight: .demiBold))
                    .foregroundStyle(Color.coral)
                Text("safes left")
                    .font(.avenir(15, weight: .medium, italic: true))
                    .foregroundStyle(Color.ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8),
                spacing: 5
            ) {
                ForEach(allSafes, id: \.self) { safe in
                    safeCell(value: safe, available: availableSafes.contains(safe))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.ink.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func safeCell(value: Int, available: Bool) -> some View {
        let coins = tileCoinsForView(value)

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    available
                        ? LinearGradient(
                            colors: [Color.safePeachLight, Color.safePeachDark],
                            startPoint: .top,
                            endPoint: .bottom
                          )
                        : LinearGradient(
                            colors: [Color.ink.opacity(0.08), Color.ink.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                          )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            available ? Color.treasureInk : Color.treasureInk.opacity(0.35),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.treasureInk.opacity(available ? 0.18 : 0), radius: 0, x: 0, y: 2)

            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(18, weight: .demiBold))
                    .foregroundStyle(available ? Color.treasureInk : Color.treasureInk.opacity(0.45))
                CoinPips(count: coins, diameter: 6, spacing: 3)
                    .opacity(available ? 1.0 : 0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .opacity(available ? 1.0 : 0.6)
    }

    private func tileCoinsForView(_ safe: Int) -> Int {
        if safe <= 24 { return 1 }
        if safe <= 28 { return 2 }
        if safe <= 32 { return 3 }
        return 4
    }
}
