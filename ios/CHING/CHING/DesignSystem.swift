import SwiftUI
import UIKit

// MARK: - Palette (Monument Valley)

extension Color {
    /// Top of sky gradient (light: cream peach, dark: deep plum).
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 61/255, green: 46/255, blue: 72/255, alpha: 1)
            : UIColor(red: 251/255, green: 231/255, blue: 208/255, alpha: 1)
    })

    /// All type and borders (light: deep plum, dark: cream).
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 251/255, green: 231/255, blue: 208/255, alpha: 1)
            : UIColor(red: 74/255, green: 55/255, blue: 84/255, alpha: 1)
    })

    /// Secondary text / dim borders (light: soft plum, dark: dusky lavender).
    static let dimInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 168/255, green: 154/255, blue: 184/255, alpha: 1)
            : UIColor(red: 122/255, green: 95/255, blue: 132/255, alpha: 1)
    })

    /// Coral accent — active seat, action stamp.
    static let coral = Color(red: 210/255, green: 116/255, blue: 116/255)
    /// Brighter coral for highlight on the stamp button (top of the gradient).
    static let coralLight = Color(red: 238/255, green: 158/255, blue: 158/255)

    /// Coral darker — stamp drop shadow.
    static let coralDark = Color(red: 168/255, green: 88/255, blue: 88/255)

    /// Gold pip — coin value markers on safes.
    static let gold = Color(red: 201/255, green: 140/255, blue: 74/255)

    /// Constant deep plum for text + borders on the peach treasure assets
    /// (safes, dice, vault chips). Doesn't invert in dark mode — these
    /// are physical objects, not chrome.
    static let treasureInk = Color(red: 74/255, green: 55/255, blue: 84/255)

    /// Constant cream for stamp button text on the coral fill.
    /// Doesn't invert — coral is constant, text on it is constant too.
    static let stampText = Color(red: 251/255, green: 231/255, blue: 208/255)

    /// Safe tile gradient stops (peach).
    static let safePeachLight = Color(red: 253/255, green: 233/255, blue: 208/255)
    static let safePeachDark = Color(red: 243/255, green: 214/255, blue: 184/255)

    /// Coin die face gradient stops (gold).
    static let coinGoldLight = Color(red: 250/255, green: 219/255, blue: 150/255)
    static let coinGoldDark = Color(red: 240/255, green: 201/255, blue: 122/255)

    // MARK: - Sky gradient stops

    static let skyTop = paper

    static let skyMid = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 90/255, green: 69/255, blue: 113/255, alpha: 1)
            : UIColor(red: 245/255, green: 205/255, blue: 160/255, alpha: 1)
    })

    static let skyLavender = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 138/255, green: 106/255, blue: 138/255, alpha: 1)
            : UIColor(red: 210/255, green: 182/255, blue: 208/255, alpha: 1)
    })

    static let skyPlum = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 168/255, green: 154/255, blue: 184/255, alpha: 1)
            : UIColor(red: 165/255, green: 148/255, blue: 184/255, alpha: 1)
    })

    // MARK: - Architectural silhouette

    static let citySilhouette = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 50/255, green: 38/255, blue: 60/255, alpha: 0.85)
            : UIColor(red: 139/255, green: 100/255, blue: 136/255, alpha: 0.7)
    })

    static let citySilhouetteAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 70/255, green: 53/255, blue: 84/255, alpha: 0.85)
            : UIColor(red: 168/255, green: 128/255, blue: 165/255, alpha: 0.7)
    })

    // MARK: - Moon

    static let moonGlow = Color(red: 245/255, green: 212/255, blue: 155/255)
    static let moonCenter = Color(red: 255/255, green: 248/255, blue: 232/255)
}

// MARK: - Typography (Avenir Next, single-family)

enum AvenirWeight {
    case ultraLight, regular, medium, demiBold, bold

    func postScriptName(italic: Bool) -> String {
        switch (self, italic) {
        case (.ultraLight, false): return "AvenirNext-UltraLight"
        case (.ultraLight, true):  return "AvenirNext-UltraLightItalic"
        case (.regular, false):    return "AvenirNext-Regular"
        case (.regular, true):     return "AvenirNext-Italic"
        case (.medium, false):     return "AvenirNext-Medium"
        case (.medium, true):      return "AvenirNext-MediumItalic"
        case (.demiBold, false):   return "AvenirNext-DemiBold"
        case (.demiBold, true):    return "AvenirNext-DemiBoldItalic"
        case (.bold, false):       return "AvenirNext-Bold"
        case (.bold, true):        return "AvenirNext-BoldItalic"
        }
    }
}

extension Font {
    static func avenir(_ size: CGFloat, weight: AvenirWeight = .regular, italic: Bool = false) -> Font {
        .custom(weight.postScriptName(italic: italic), size: size)
    }

    // Legacy Phase 4 font helpers — redirected to Avenir so the existing code
    // builds against the MV typography while we migrate component-by-component.
    static func cochin(_ size: CGFloat) -> Font { .avenir(size, weight: .regular) }
    static func cochinItalic(_ size: CGFloat) -> Font { .avenir(size, weight: .medium, italic: true) }
    static func bodoni(_ size: CGFloat) -> Font { .avenir(size, weight: .demiBold) }
    static func bodoniItalic(_ size: CGFloat) -> Font { .avenir(size, weight: .demiBold, italic: true) }
}

// MARK: - CoinPips

struct CoinPips: View {
    let count: Int
    var diameter: CGFloat = 5
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(0, count), id: \.self) { _ in
                Circle()
                    .fill(Color.gold)
                    .frame(width: diameter, height: diameter)
            }
        }
    }
}

// MARK: - Stamp button (MV coral pill)

struct StampButtonStyle: ButtonStyle {
    var primary: Bool = true
    var invite: Bool = false

    @SwiftUI.State private var pulse: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.avenir(16, weight: .demiBold))
            .textCase(.uppercase)
            .tracking(3)
            .foregroundStyle(primary ? Color.stampText : Color.coral)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            primary
                                ? LinearGradient(
                                    colors: [Color.coinGoldLight, Color.coralLight, Color.coral, Color.coralDark],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  )
                                : LinearGradient(
                                    colors: [Color.stampText, Color.stampText.opacity(0.88)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                  )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    primary ? Color.coralDark.opacity(0.7) : Color.coral,
                                    lineWidth: primary ? 1 : 1.5
                                )
                        )
                        .overlay(
                            // Top-edge inner highlight to read as a lit surface
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(primary ? 0.55 : 0.0),
                                            Color.white.opacity(0.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 1.2
                                )
                                .padding(1)
                        )
                }
                // Hard-offset rim (echoes the tile depth recipe)
                .shadow(color: Color.coralDark.opacity(0.45), radius: 0, x: 0, y: 3)
                // Soft drop
                .shadow(color: Color.coralDark.opacity(0.3), radius: 10, x: 0, y: 7)
                // Invitation pulse glow
                .shadow(
                    color: invite ? Color.coral.opacity(pulse ? 0.6 : 0.15) : .clear,
                    radius: pulse ? 20 : 8,
                    x: 0,
                    y: 0
                )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : (invite && pulse ? 1.015 : 1.0))
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .onAppear {
                guard invite else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func stampButton(primary: Bool = true, invite: Bool = false) -> some View {
        self.buttonStyle(StampButtonStyle(primary: primary, invite: invite))
    }
}

// MARK: - Tiny shadow modifier (legacy, soft now)

struct StampShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color.ink.opacity(0.22), radius: 0, x: 0, y: 3)
    }
}

extension View {
    func stampShadow() -> some View {
        modifier(StampShadowModifier())
    }
}
