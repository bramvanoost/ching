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

    /// Tiny glyph — reads as a pinpoint sparkle, not an orb.
    private var glyphSize: CGFloat {
        3 + CGFloat(seed * 11 % 5)
    }

    /// Just enough stagger to avoid a single-frame pop. Most sparkles
    /// appear effectively instantly.
    private var delay: Double {
        Double(seed * 3 % 11) / 11.0 * 0.12
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
            // Start visible at the edge, drift outward as it fades.
            .offset(x: go ? endX : startX, y: go ? endY : startY)
            .opacity(go ? 0 : 1)
            .scaleEffect(go ? 0.4 : 1.2)
            .animation(.easeOut(duration: duration).delay(delay), value: go)
    }
}

/// Sparkles distributed along the perimeter of the host view's frame and
/// drifting outward, perpendicular to whichever edge they were born on.
/// Use as an overlay on a card to ring it in tiny gold flecks.
struct EdgeSparkleField: View {
    var count: Int = 70
    var inset: CGFloat = 4
    var spread: CGFloat = 16
    var duration: Double = 1.4

    @SwiftUI.State private var go: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    EdgeSparkle(
                        seed: i,
                        size: geo.size,
                        inset: inset,
                        spread: spread,
                        duration: duration,
                        go: go
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation { go = true }
        }
    }
}

private struct EdgeSparkle: View {
    let seed: Int
    let size: CGSize
    let inset: CGFloat
    let spread: CGFloat
    let duration: Double
    let go: Bool

    /// Position 0..<1 along the perimeter walk: top → right → bottom → left.
    private var perimeterT: CGFloat {
        CGFloat((seed * 911) % 1009) / 1009.0
    }

    private var glyphSize: CGFloat {
        3 + CGFloat((seed * 7) % 4)
    }

    private var delay: Double {
        Double((seed * 13) % 17) / 17.0 * 0.45
    }

    private var rotation: Double {
        Double((seed * 31) % 360)
    }

    private struct EdgePoint { let point: CGPoint; let normal: CGVector }

    private func walkEdge() -> EdgePoint {
        let w = size.width
        let h = size.height
        let perim = 2 * (w + h)
        let d = perimeterT * perim
        if d < w {
            return EdgePoint(point: CGPoint(x: d, y: inset),
                             normal: CGVector(dx: 0, dy: -1))
        }
        if d < w + h {
            return EdgePoint(point: CGPoint(x: w - inset, y: d - w),
                             normal: CGVector(dx: 1, dy: 0))
        }
        if d < 2 * w + h {
            return EdgePoint(point: CGPoint(x: w - (d - w - h), y: h - inset),
                             normal: CGVector(dx: 0, dy: 1))
        }
        return EdgePoint(point: CGPoint(x: inset, y: h - (d - 2 * w - h)),
                         normal: CGVector(dx: -1, dy: 0))
    }

    var body: some View {
        let edge = walkEdge()
        let endX = edge.point.x + edge.normal.dx * spread
        let endY = edge.point.y + edge.normal.dy * spread
        Image(systemName: "sparkle")
            .font(.system(size: glyphSize, weight: .bold))
            .foregroundStyle(Color.coinGoldLight)
            .shadow(color: Color.moonCenter.opacity(0.9), radius: 1.5, x: 0, y: 0)
            .shadow(color: Color.gold.opacity(0.6), radius: 3, x: 0, y: 0)
            .rotationEffect(.degrees(rotation))
            .position(x: go ? endX : edge.point.x, y: go ? endY : edge.point.y)
            .opacity(go ? 0 : 1)
            .scaleEffect(go ? 0.4 : 1.2)
            .animation(.easeOut(duration: duration).delay(delay), value: go)
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
