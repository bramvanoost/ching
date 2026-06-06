import Foundation
import Observation
import SwiftUI

enum ColorMode: String, Codable, CaseIterable {
    case system, light, dark

    var preferredScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SoundMode: String, Codable, CaseIterable {
    case all      // music + game SFX
    case gameOnly // SFX only, home music silent
    case muted    // silent everywhere
}

@MainActor
@Observable
final class SettingsStore {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"
    private static let soundModeKey = "ching.soundMode"

    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
    }

    var colorMode: ColorMode {
        didSet {
            UserDefaults.standard.set(colorMode.rawValue, forKey: Self.colorModeKey)
        }
    }

    var reducedMotion: Bool {
        didSet {
            UserDefaults.standard.set(reducedMotion, forKey: Self.reducedMotionKey)
        }
    }

    var soundMode: SoundMode {
        didSet {
            UserDefaults.standard.set(soundMode.rawValue, forKey: Self.soundModeKey)
            AudioPolicy.shared.applySoundMode(soundMode)
        }
    }

    init() {
        let rawDiff = UserDefaults.standard.string(forKey: Self.difficultyKey) ?? ""
        self.difficulty = Difficulty(rawValue: rawDiff) ?? .normal

        let rawMode = UserDefaults.standard.string(forKey: Self.colorModeKey) ?? ""
        self.colorMode = ColorMode(rawValue: rawMode) ?? .system

        self.reducedMotion = UserDefaults.standard.bool(forKey: Self.reducedMotionKey)

        let rawSound = UserDefaults.standard.string(forKey: Self.soundModeKey) ?? ""
        self.soundMode = SoundMode(rawValue: rawSound) ?? .all

        AudioPolicy.shared.applySoundMode(soundMode)
    }
}
