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

            // Moon, top-right
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.moonGlow)
                        .frame(width: 60, height: 60)
                        .blur(radius: 18)
                        .opacity(0.55)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.moonCenter, Color.moonGlow, Color.moonGlow.opacity(0.6)],
                                center: UnitPoint(x: 0.35, y: 0.35),
                                startRadius: 2,
                                endRadius: 22
                            )
                        )
                        .frame(width: 38, height: 38)
                }
                .position(x: geo.size.width - 50, y: 90)
            }

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

    private let pillars: [Pillar] = [
        Pillar(x: 30, width: 40, height: 80, accent: false),
        Pillar(x: 78, width: 32, height: 112, accent: false),
        Pillar(x: 120, width: 52, height: 64, accent: true),
        Pillar(x: 184, width: 36, height: 96, accent: false),
        Pillar(x: 236, width: 44, height: 72, accent: false),
        Pillar(x: 290, width: 32, height: 88, accent: true),
        Pillar(x: 336, width: 40, height: 60, accent: false)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(pillars.indices, id: \.self) { idx in
                    let p = pillars[idx]
                    IsoPillar(width: p.width, height: p.height, accent: p.accent)
                        .offset(x: p.x, y: baseY - p.height)
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
