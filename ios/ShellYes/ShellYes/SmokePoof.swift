import SwiftUI

/// Short, soft burst of cream puffs drifting up-and-out before fading.
/// Used when a shell is taken from a rival's vault — the visual answer
/// to "where did it go?" Reads as "*poof*, just removed from the world."
///
/// Pairs with `SparkleField` on the receiving side: the loss feels
/// physical, the gain feels celebratory.
struct SmokePoof: View {
    var count: Int = 7
    var duration: Double = 0.75
    var spread: CGFloat = 22

    @SwiftUI.State private var go: Bool = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                SmokePuff(seed: i, count: count, duration: duration, spread: spread, go: go)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation { go = true }
        }
    }
}

private struct SmokePuff: View {
    let seed: Int
    let count: Int
    let duration: Double
    let spread: CGFloat
    let go: Bool

    private var angle: Double {
        let base = Double(seed) / Double(count) * .pi * 2
        let jitter = (Double(seed * 17 % 31) / 31.0 - 0.5) * 0.6
        return base + jitter
    }

    private var distance: CGFloat {
        let base = spread * 0.7
        let extra = CGFloat(seed * 13 % 20) * (spread / 80)
        return base + extra
    }

    private var size: CGFloat {
        12 + CGFloat(seed * 11 % 8)
    }

    /// Bias the whole cloud upward so it reads as smoke rising.
    private var verticalBias: CGFloat {
        -10 - CGFloat(seed * 3 % 8)
    }

    private var delay: Double {
        Double(seed * 5 % 11) / 11.0 * 0.08
    }

    var body: some View {
        let endX = cos(angle) * distance
        let endY = sin(angle) * distance + verticalBias

        Circle()
            .fill(Color(red: 245/255, green: 232/255, blue: 218/255))
            .frame(width: size, height: size)
            .blur(radius: 4)
            .scaleEffect(go ? 1.9 : 0.3)
            .offset(x: go ? endX : 0, y: go ? endY : 0)
            .opacity(go ? 0 : 0.7)
            .animation(.easeOut(duration: duration).delay(delay), value: go)
    }
}

#Preview {
    ZStack {
        Color.skyMid.ignoresSafeArea()
        SmokePoof()
            .frame(width: 60, height: 60)
    }
}
