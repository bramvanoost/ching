import SwiftUI
import CHINGEngine

struct VaultStack: View {
    let safes: [Int]
    var activeSeat: Bool = false

    private let safeWidth: CGFloat = 38
    private let safeHeight: CGFloat = 34
    private let layerOffset: CGFloat = 5

    private var stackHeight: CGFloat {
        if safes.isEmpty { return 36 }
        return safeHeight + CGFloat(max(0, safes.count - 1)) * layerOffset
    }

    /// Newest first (top of pile). Engine stores newest at end of `tiles`.
    private var stackedNewestFirst: [Int] {
        safes.reversed()
    }

    var body: some View {
        if safes.isEmpty {
            EmptyView()
        } else {
            ZStack(alignment: .top) {
                ForEach(Array(stackedNewestFirst.enumerated()), id: \.offset) { idx, safe in
                    safeView(value: safe, isTop: idx == 0)
                        .offset(y: CGFloat(idx) * layerOffset)
                        .zIndex(Double(stackedNewestFirst.count - idx))
                }
            }
            .frame(width: safeWidth, height: stackHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private func safeView(value: Int, isTop: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.ink, lineWidth: 1.5)
                )
                .shadow(color: Color.ink.opacity(0.15), radius: 0, x: 0, y: 2)

            if isTop {
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(.avenir(13, weight: .demiBold))
                        .foregroundStyle(Color.ink)
                    CoinPips(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
                }
            }
        }
        .frame(width: safeWidth, height: safeHeight)
    }
}
