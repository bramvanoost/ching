import SwiftUI

/// The Monument-Valley-inspired atmospheric background.
/// Sky gradient + moon + cityscape silhouette + soft ground.
struct Background: View {
    var body: some View {
        ZStack {
            // Sky gradient
            LinearGradient(
                stops: [
                    .init(color: .skyTop, location: 0.0),
                    .init(color: .skyMid, location: 0.35),
                    .init(color: .skyLavender, location: 0.70),
                    .init(color: .skyPlum, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Cityscape silhouette
            GeometryReader { geo in
                ZStack {
                    Skyline(
                        baseY: geo.size.height - 120
                    )
                }
            }
            .allowsHitTesting(false)
            .opacity(0.85)
        }
        .ignoresSafeArea()
    }
}

/// A row of isometric architectural pillars receding into the horizon.
private struct Skyline: View {
    let baseY: CGFloat

    private struct Pillar {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
        var accent: Bool
    }

    // Smaller, further apart pillars — recede into the background like a distant skyline
    private let pillars: [Pillar] = [
        Pillar(x: 24, width: 22, height: 44, accent: false),
        Pillar(x: 58, width: 18, height: 62, accent: false),
        Pillar(x: 92, width: 28, height: 36, accent: true),
        Pillar(x: 136, width: 20, height: 56, accent: false),
        Pillar(x: 172, width: 24, height: 40, accent: true),
        Pillar(x: 212, width: 18, height: 50, accent: false),
        Pillar(x: 246, width: 26, height: 32, accent: false),
        Pillar(x: 286, width: 20, height: 48, accent: true),
        Pillar(x: 320, width: 22, height: 38, accent: false),
        Pillar(x: 356, width: 18, height: 54, accent: false)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(pillars.indices, id: \.self) { idx in
                    let p = pillars[idx]
                    IsoPillar(width: p.width, height: p.height, accent: p.accent)
                        .offset(x: p.x, y: baseY - p.height)
                        .opacity(0.65)
                }

                // Soft ground gradient — extends to the bottom of the screen
                // (and below, via ignoresSafeArea) so it never shows a hard cutoff line.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.citySilhouette.opacity(0.0),
                                Color.citySilhouette.opacity(0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(200, geo.size.height - baseY + 200))
                    .offset(y: baseY)
            }
        }
    }
}

private struct IsoPillar: View {
    let width: CGFloat
    let height: CGFloat
    let accent: Bool

    var body: some View {
        let leftColor = accent ? Color.citySilhouetteAccent : Color.citySilhouette
        let rightColor = accent ? Color.citySilhouette : Color.citySilhouetteAccent
        let topColor = accent ? Color.citySilhouetteAccent.opacity(0.85) : Color.citySilhouette.opacity(0.85)

        ZStack(alignment: .topLeading) {
            // Left face
            Path { path in
                path.move(to: CGPoint(x: 0, y: 8))
                path.addLine(to: CGPoint(x: width / 2, y: 0))
                path.addLine(to: CGPoint(x: width / 2, y: height))
                path.addLine(to: CGPoint(x: 0, y: height - 8))
                path.closeSubpath()
            }
            .fill(leftColor)

            // Right face
            Path { path in
                path.move(to: CGPoint(x: width / 2, y: 0))
                path.addLine(to: CGPoint(x: width, y: 8))
                path.addLine(to: CGPoint(x: width, y: height - 8))
                path.addLine(to: CGPoint(x: width / 2, y: height))
                path.closeSubpath()
            }
            .fill(rightColor)

            // Top diamond
            Path { path in
                path.move(to: CGPoint(x: 0, y: 8))
                path.addLine(to: CGPoint(x: width / 2, y: 0))
                path.addLine(to: CGPoint(x: width, y: 8))
                path.addLine(to: CGPoint(x: width / 2, y: 16))
                path.closeSubpath()
            }
            .fill(topColor)
        }
        .frame(width: width, height: height)
    }
}

#Preview {
    Background()
}
