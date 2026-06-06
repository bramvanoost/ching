import SwiftUI

/// The Monument-Valley-inspired atmospheric background.
/// Sky gradient + distant cityscape silhouette.
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

            // Distant cityscape silhouette
            GeometryReader { geo in
                Cityscape(baseY: geo.size.height - 110)
                    .opacity(0.5)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.55),
                                .init(color: .black, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// A row of overlapping isometric buildings of varied types and sizes,
/// receding into the horizon haze. Soft ground gradient anchors the bottom.
private struct Cityscape: View {
    let baseY: CGFloat

    private struct Building {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
        var z: Int            // higher z = drawn later (in front)
        var accent: Bool
        var peak: Bool
        var windowRows: Int   // 0 = no windows
    }

    /// Hand-tuned layout: overlapping buildings, varied sizes, mix of plain
    /// blocks, peaked towers, and window-grids. Sorted by z so foreground
    /// buildings draw last.
    private static let buildings: [Building] = [
        Building(x:  -8, width: 30, height: 64, z: 0, accent: false, peak: false, windowRows: 2),
        Building(x:  22, width: 18, height: 86, z: 1, accent: false, peak: true,  windowRows: 0),
        Building(x:  44, width: 36, height: 50, z: 0, accent: true,  peak: false, windowRows: 1),
        Building(x:  72, width: 22, height: 72, z: 2, accent: false, peak: false, windowRows: 2),
        Building(x: 100, width: 28, height: 44, z: 0, accent: false, peak: false, windowRows: 1),
        Building(x: 122, width: 18, height: 96, z: 2, accent: true,  peak: true,  windowRows: 0),
        Building(x: 144, width: 32, height: 58, z: 1, accent: false, peak: false, windowRows: 2),
        Building(x: 178, width: 22, height: 40, z: 0, accent: false, peak: false, windowRows: 1),
        Building(x: 196, width: 26, height: 68, z: 2, accent: true,  peak: false, windowRows: 2),
        Building(x: 226, width: 20, height: 80, z: 1, accent: false, peak: true,  windowRows: 0),
        Building(x: 250, width: 30, height: 52, z: 0, accent: false, peak: false, windowRows: 1),
        Building(x: 278, width: 18, height: 90, z: 2, accent: true,  peak: false, windowRows: 2),
        Building(x: 302, width: 28, height: 48, z: 1, accent: false, peak: false, windowRows: 1),
        Building(x: 328, width: 20, height: 70, z: 2, accent: false, peak: true,  windowRows: 0),
        Building(x: 352, width: 30, height: 40, z: 0, accent: true,  peak: false, windowRows: 1),
        Building(x: 382, width: 16, height: 60, z: 1, accent: false, peak: false, windowRows: 2)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.buildings.enumerated()), id: \.offset) { _, b in
                    BuildingView(
                        width: b.width,
                        height: b.height,
                        accent: b.accent,
                        peak: b.peak,
                        windowRows: b.windowRows
                    )
                    .offset(x: b.x, y: baseY - b.height)
                    .zIndex(Double(b.z))
                }

                // Soft ground gradient extends below to avoid a hard cutoff.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.citySilhouette.opacity(0.0),
                                Color.citySilhouette.opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(200, geo.size.height - baseY + 200))
                    .offset(y: baseY)
                    .zIndex(-1)
            }
        }
    }
}

private struct BuildingView: View {
    let width: CGFloat
    let height: CGFloat
    let accent: Bool
    let peak: Bool
    let windowRows: Int

    var body: some View {
        let leftColor = accent ? Color.citySilhouetteAccent : Color.citySilhouette
        let rightColor = accent ? Color.citySilhouette : Color.citySilhouetteAccent
        let topColor = accent ? Color.citySilhouetteAccent.opacity(0.9) : Color.citySilhouette.opacity(0.9)

        // Body height stops below peak room
        let peakHeight: CGFloat = peak ? min(width * 0.45, 18) : 0
        let bodyTop: CGFloat = peakHeight
        let bodyHeight: CGFloat = height - peakHeight

        ZStack(alignment: .topLeading) {
            // Optional triangular peak on top of body
            if peak {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: peakHeight + 6))
                    path.addLine(to: CGPoint(x: width / 2, y: 0))
                    path.addLine(to: CGPoint(x: width, y: peakHeight + 6))
                    path.closeSubpath()
                }
                .fill(leftColor)
            }

            // Left face
            Path { path in
                path.move(to: CGPoint(x: 0, y: bodyTop + 8))
                path.addLine(to: CGPoint(x: width / 2, y: bodyTop))
                path.addLine(to: CGPoint(x: width / 2, y: bodyTop + bodyHeight))
                path.addLine(to: CGPoint(x: 0, y: bodyTop + bodyHeight - 8))
                path.closeSubpath()
            }
            .fill(leftColor)

            // Right face
            Path { path in
                path.move(to: CGPoint(x: width / 2, y: bodyTop))
                path.addLine(to: CGPoint(x: width, y: bodyTop + 8))
                path.addLine(to: CGPoint(x: width, y: bodyTop + bodyHeight - 8))
                path.addLine(to: CGPoint(x: width / 2, y: bodyTop + bodyHeight))
                path.closeSubpath()
            }
            .fill(rightColor)

            // Top diamond (only if not peaked)
            if !peak {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: bodyTop + 8))
                    path.addLine(to: CGPoint(x: width / 2, y: bodyTop))
                    path.addLine(to: CGPoint(x: width, y: bodyTop + 8))
                    path.addLine(to: CGPoint(x: width / 2, y: bodyTop + 16))
                    path.closeSubpath()
                }
                .fill(topColor)
            }

            // Windows on the front faces (left + right)
            if windowRows > 0 {
                windowGrid(bodyTop: bodyTop, bodyHeight: bodyHeight)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func windowGrid(bodyTop: CGFloat, bodyHeight: CGFloat) -> some View {
        let rows = windowRows
        let topPadding: CGFloat = 12
        let bottomPadding: CGFloat = 8
        let rowSpacing = max(8, (bodyHeight - topPadding - bottomPadding) / CGFloat(max(1, rows)))
        let windowColor = Color.skyTop.opacity(0.55)

        // Left face windows
        ForEach(0..<rows, id: \.self) { r in
            let y = bodyTop + topPadding + CGFloat(r) * rowSpacing
            Rectangle()
                .fill(windowColor)
                .frame(width: 3, height: 3)
                .offset(x: width / 2 - 8, y: y)
            Rectangle()
                .fill(windowColor)
                .frame(width: 3, height: 3)
                .offset(x: width / 2 - 4, y: y)
        }

        // Right face windows
        ForEach(0..<rows, id: \.self) { r in
            let y = bodyTop + topPadding + CGFloat(r) * rowSpacing
            Rectangle()
                .fill(windowColor)
                .frame(width: 3, height: 3)
                .offset(x: width / 2 + 1, y: y)
            Rectangle()
                .fill(windowColor)
                .frame(width: 3, height: 3)
                .offset(x: width / 2 + 5, y: y)
        }
    }
}

#Preview {
    Background()
}
