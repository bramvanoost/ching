import SwiftUI

struct SafesGrid: View {
    let availableSafes: [Int]
    let remainingCount: Int

    private let allSafes: [Int] = Array(21...36)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("\(remainingCount)")
                    .font(.cochin(18))
                    .fontWeight(.bold)
                Text("Safes left")
                    .font(.cochinItalic(18))
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                spacing: 4
            ) {
                ForEach(allSafes, id: \.self) { safe in
                    safeCell(value: safe, available: availableSafes.contains(safe))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ink).frame(height: 1)
        }
    }

    @ViewBuilder
    private func safeCell(value: Int, available: Bool) -> some View {
        let stroke = available ? Color.ink : Color.dimInk
        let fg = available ? Color.ink : Color.dimInk
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.cochin(14))
                .foregroundStyle(fg)
            Text("\(tileCoinsForView(value))c")
                .font(.cochinItalic(8))
                .foregroundStyle(fg.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(available ? Color.paper : Color.dimInk.opacity(0.08))
        .overlay(Rectangle().strokeBorder(stroke, lineWidth: 1.5))
    }

    private func tileCoinsForView(_ safe: Int) -> Int {
        if safe <= 24 { return 1 }
        if safe <= 28 { return 2 }
        if safe <= 32 { return 3 }
        return 4
    }
}
