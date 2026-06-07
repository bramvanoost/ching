import SwiftUI

struct SafesGrid: View {
    let availableSafes: [Int]
    let remainingCount: Int
    var revealed: Bool = true

    private let allSafes: [Int] = Array(21...36)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 5) {
                Text("\(remainingCount)")
                    .font(.avenir(18, weight: .demiBold))
                    .foregroundStyle(Color.ink)
                Text("shells on the sand")
                    .font(.avenir(18, weight: .medium, italic: true))
                    .foregroundStyle(Color.ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: revealed)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8),
                spacing: 5
            ) {
                ForEach(Array(allSafes.enumerated()), id: \.offset) { idx, safe in
                    safeCell(value: safe, available: availableSafes.contains(safe))
                        .opacity(revealed ? 1 : 0)
                        .scaleEffect(revealed ? 1 : 0.5)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7).delay(Double(idx) * 0.035),
                            value: revealed
                        )
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
        ZStack {
            // Base layer — dim unavailable styling, always rendered
            cellLayer(value: value, available: false)

            // Active layer — rendered only when available. On removal it
            // punches forward (2.2× scale) and fades, so the tile clearly
            // leaves the pool toward the player's vault.
            if available {
                cellLayer(value: value, available: true)
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 2.2).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .animation(.easeOut(duration: 0.7), value: available)
    }

    @ViewBuilder
    private func cellLayer(value: Int, available: Bool) -> some View {
        let coins = tileCoinsForView(value)

        ZStack {
            ShellCardShape()
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
                    ShellCardShape()
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
                PearlRow(count: coins, diameter: 6, spacing: 3)
                    .opacity(available ? 1.0 : 0.3)
            }
        }
        .opacity(available ? 1.0 : 0.6)
    }

    private func tileCoinsForView(_ safe: Int) -> Int {
        if safe <= 24 { return 1 }
        if safe <= 28 { return 2 }
        if safe <= 32 { return 3 }
        return 4
    }
}
