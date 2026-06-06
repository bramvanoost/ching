import SwiftUI

/// A burst of gold particles emanating from the center of its frame.
/// Triggers once when the view appears.
struct SparkleField: View {
    var count: Int = 16
    var spread: CGFloat = 90
    var duration: Double = 1.4

    @SwiftUI.State private var go: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Sparkle(
                    seed: i,
                    count: count,
                    spread: spread,
                    duration: duration,
                    go: go
                )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation {
                go = true
            }
        }
    }
}

private struct Sparkle: View {
    let seed: Int
    let count: Int
    let spread: CGFloat
    let duration: Double
    let go: Bool

    private var angle: Double {
        // Spread evenly around 360°, with a small random jitter from seed.
        let base = Double(seed) / Double(count) * .pi * 2
        let jitter = (Double(seed * 13 % 31) / 31.0 - 0.5) * 0.35
        return base + jitter
    }

    private var distance: CGFloat {
        let base = spread * 0.55
        let extra = CGFloat(seed * 7 % 30) * (spread / 100)
        return base + extra
    }

    private var dieSize: CGFloat {
        4 + CGFloat(seed * 11 % 6)
    }

    private var delay: Double {
        Double(seed * 5 % 13) / 13.0 * 0.18
    }

    var body: some View {
        let endX = cos(angle) * distance
        let endY = sin(angle) * distance

        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.moonCenter, Color.gold],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: dieSize, height: dieSize)
            .shadow(color: Color.gold.opacity(0.7), radius: 4, x: 0, y: 0)
            .offset(x: go ? endX : 0, y: go ? endY : 0)
            .opacity(go ? 0 : 1)
            .scaleEffect(go ? 0.4 : 1.3)
            .animation(
                .easeOut(duration: duration).delay(delay),
                value: go
            )
    }
}

#Preview {
    ZStack {
        Color.skyMid.ignoresSafeArea()
        SparkleField()
    }
}
