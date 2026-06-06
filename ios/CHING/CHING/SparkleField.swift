import SwiftUI

/// A burst of bright gold particles emanating outward from the edge of
/// the host view in 360 degrees. Triggers once when the view appears.
struct SparkleField: View {
    var count: Int = 16
    var startRadius: CGFloat = 0
    var spread: CGFloat = 90
    var duration: Double = 1.4

    @SwiftUI.State private var go: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Sparkle(
                    seed: i,
                    count: count,
                    startRadius: startRadius,
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
    let startRadius: CGFloat
    let spread: CGFloat
    let duration: Double
    let go: Bool

    private var angle: Double {
        let base = Double(seed) / Double(count) * .pi * 2
        let jitter = (Double(seed * 13 % 31) / 31.0 - 0.5) * 0.5
        return base + jitter
    }

    private var travelDistance: CGFloat {
        let base = spread * 0.55
        let extra = CGFloat(seed * 7 % 30) * (spread / 100)
        return base + extra
    }

    private var dieSize: CGFloat {
        // Bigger, brighter particles
        7 + CGFloat(seed * 11 % 8)
    }

    private var delay: Double {
        Double(seed * 5 % 13) / 13.0 * 0.18
    }

    var body: some View {
        let startX = cos(angle) * startRadius
        let startY = sin(angle) * startRadius
        let endX = cos(angle) * (startRadius + travelDistance)
        let endY = sin(angle) * (startRadius + travelDistance)

        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.moonCenter, Color.coinGoldLight, Color.gold],
                    center: UnitPoint(x: 0.4, y: 0.4),
                    startRadius: 0,
                    endRadius: dieSize / 2
                )
            )
            .frame(width: dieSize, height: dieSize)
            .shadow(color: Color.coinGoldLight, radius: 4, x: 0, y: 0)
            .shadow(color: Color.gold.opacity(0.9), radius: 8, x: 0, y: 0)
            .shadow(color: Color.gold.opacity(0.5), radius: 16, x: 0, y: 0)
            .offset(x: go ? endX : startX, y: go ? endY : startY)
            .opacity(go ? 0 : 1)
            .scaleEffect(go ? 0.3 : 1.4)
            .animation(
                .easeOut(duration: duration).delay(delay),
                value: go
            )
    }
}

#Preview {
    ZStack {
        Color.skyMid.ignoresSafeArea()
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.safePeachLight)
                .frame(width: 60, height: 60)
                .overlay(
                    SparkleField(count: 14, startRadius: 30, spread: 60)
                )
        }
    }
}
