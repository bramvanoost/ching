import SwiftUI
import UIKit

extension Color {
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
            : UIColor(red: 250/255, green: 248/255, blue: 243/255, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 250/255, green: 248/255, blue: 243/255, alpha: 1)
            : UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
    })

    static let dimInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 154/255, green: 154/255, blue: 154/255, alpha: 1)
            : UIColor(red: 107/255, green: 107/255, blue: 107/255, alpha: 1)
    })

    /// Antique-gold accent for coin pips. Same hex in light and dark; gold
    /// reads on both warm cream and near-black backgrounds.
    static let gold = Color(red: 201/255, green: 169/255, blue: 97/255)
}

/// Small row of gold filled circles for coin value (1-4). Used on safes
/// to make their coin value glance-readable.
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

extension Font {
    static func cochin(_ size: CGFloat) -> Font {
        .custom("Cochin", size: size)
    }

    static func cochinItalic(_ size: CGFloat) -> Font {
        .custom("Cochin-Italic", size: size)
    }

    static func bodoni(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-Book", size: size)
    }

    static func bodoniItalic(_ size: CGFloat) -> Font {
        .custom("BodoniSvtyTwoITCTT-BookIta", size: size)
    }
}

struct StampShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color.ink, radius: 0, x: 2, y: 2)
    }
}

extension View {
    func stampShadow() -> some View {
        modifier(StampShadowModifier())
    }
}

struct StampButtonStyle: ButtonStyle {
    var primary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodoni(16))
            .textCase(.uppercase)
            .tracking(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .foregroundStyle(primary ? Color.paper : Color.ink)
            .background(primary ? Color.ink : Color.paper)
            .overlay(
                Rectangle().strokeBorder(Color.ink, lineWidth: 1.5)
            )
            .stampShadow()
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension View {
    func stampButton(primary: Bool = false) -> some View {
        self.buttonStyle(StampButtonStyle(primary: primary))
    }
}
