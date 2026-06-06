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
        let base = spread * 0.6
        let extra = CGFloat(seed * 7 % 30) * (spread / 100)
        return base + extra
    }

    /// Glyph size — small enough to twinkle, not glow like an orb.
    private var glyphSize: CGFloat {
        4 + CGFloat(seed * 11 % 6)
    }

    /// Each sparkle starts at a different point in the twinkle so the burst
    /// shimmers instead of pulsing in sync.
    private var delay: Double {
        Double(seed * 5 % 17) / 17.0 * (duration * 0.5)
    }

    private var rotation: Double {
        Double(seed * 47 % 90) - 45
    }

    var body: some View {
        let startX = cos(angle) * startRadius
        let startY = sin(angle) * startRadius
        let endX = cos(angle) * (startRadius + travelDistance)
        let endY = sin(angle) * (startRadius + travelDistance)

        Image(systemName: "sparkle")
            .font(.system(size: glyphSize, weight: .bold))
            .foregroundStyle(Color.coinGoldLight)
            .shadow(color: Color.moonCenter.opacity(0.9), radius: 1.5, x: 0, y: 0)
            .shadow(color: Color.gold.opacity(0.6), radius: 3, x: 0, y: 0)
            .rotationEffect(.degrees(rotation))
            // Drift outward — monotonic
            .offset(x: go ? endX : startX, y: go ? endY : startY)
            .animation(.easeOut(duration: duration).delay(delay), value: go)
            // Twinkle the brightness — 0 → 1 → 0
            .opacity(go ? 1 : 0)
            .animation(
                .easeInOut(duration: duration / 2)
                    .repeatCount(2, autoreverses: true)
                    .delay(delay),
                value: go
            )
            // Twinkle the size — small → full → small
            .scaleEffect(go ? 1.0 : 0.2)
            .animation(
                .easeInOut(duration: duration / 2)
                    .repeatCount(2, autoreverses: true)
                    .delay(delay),
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
