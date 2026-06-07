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

enum GameSpeed: String, Codable, CaseIterable {
    case slow
    case fast

    /// Multiplier on per-action delays. fast = 1.0 (current pace), slow
    /// stretches dice rolls + AI moves + pick confirmations.
    var factor: Double {
        switch self {
        case .slow: return 1.7
        case .fast: return 1.0
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"
    private static let soundModeKey = "ching.soundMode"
    private static let gameSpeedKey = "ching.gameSpeed"

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

    var gameSpeed: GameSpeed {
        didSet {
            UserDefaults.standard.set(gameSpeed.rawValue, forKey: Self.gameSpeedKey)
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

        let rawSpeed = UserDefaults.standard.string(forKey: Self.gameSpeedKey) ?? ""
        self.gameSpeed = GameSpeed(rawValue: rawSpeed) ?? .slow

        AudioPolicy.shared.applySoundMode(soundMode)
    }
}
