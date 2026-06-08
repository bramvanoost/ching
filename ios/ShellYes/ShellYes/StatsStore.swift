import Foundation
import Observation
import ShellYesEngine

/// Persistent lifetime stats for the human player. Backed by
/// UserDefaults so it survives restart. Mutations are MainActor-bound
/// and immediately persisted; SwiftUI views observe via `@Observable`.
@Observable
@MainActor
final class StatsStore {
    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let gamesPlayed         = "stats.gamesPlayed"
        static let wins                = "stats.wins"
        static let bestScore           = "stats.bestScore"
        static let busts               = "stats.busts"
        static let steals              = "stats.steals"
        static let biggestKeep         = "stats.biggestKeep"
        static let winStreak           = "stats.winStreak"
        static let bestStreak          = "stats.bestStreak"
        static let faceCounts          = "stats.faceCounts"
        static let gamesByDifficulty   = "stats.gamesByDifficulty"
        static let winsByDifficulty    = "stats.winsByDifficulty"
        static let gamesByPace         = "stats.gamesByPace"
        static let winsByPace          = "stats.winsByPace"
    }

    var gamesPlayed: Int { didSet { defaults.set(gamesPlayed, forKey: Key.gamesPlayed) } }
    var wins: Int        { didSet { defaults.set(wins, forKey: Key.wins) } }
    var bestScore: Int   { didSet { defaults.set(bestScore, forKey: Key.bestScore) } }
    var busts: Int       { didSet { defaults.set(busts, forKey: Key.busts) } }
    var steals: Int      { didSet { defaults.set(steals, forKey: Key.steals) } }
    var biggestKeep: Int { didSet { defaults.set(biggestKeep, forKey: Key.biggestKeep) } }
    var winStreak: Int   { didSet { defaults.set(winStreak, forKey: Key.winStreak) } }
    var bestStreak: Int  { didSet { defaults.set(bestStreak, forKey: Key.bestStreak) } }
    /// Tally of every face the human has set aside, keyed by Face.rawValue.
    var faceCounts: [Int: Int] {
        didSet {
            let stringKeyed = Dictionary(
                uniqueKeysWithValues: faceCounts.map { (String($0.key), $0.value) }
            )
            defaults.set(stringKeyed, forKey: Key.faceCounts)
        }
    }
    /// Per-setting tallies. Keys are the raw values of `Difficulty` /
    /// `GameSpeed` so they survive enum-case additions without a wipe.
    /// Stored as `[String: Int]` since `UserDefaults` round-trips that
    /// shape cleanly via the property list bridge.
    var gamesByDifficulty: [String: Int] { didSet { defaults.set(gamesByDifficulty, forKey: Key.gamesByDifficulty) } }
    var winsByDifficulty: [String: Int]  { didSet { defaults.set(winsByDifficulty, forKey: Key.winsByDifficulty) } }
    var gamesByPace: [String: Int]       { didSet { defaults.set(gamesByPace, forKey: Key.gamesByPace) } }
    var winsByPace: [String: Int]        { didSet { defaults.set(winsByPace, forKey: Key.winsByPace) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.gamesPlayed = defaults.integer(forKey: Key.gamesPlayed)
        self.wins        = defaults.integer(forKey: Key.wins)
        self.bestScore   = defaults.integer(forKey: Key.bestScore)
        self.busts       = defaults.integer(forKey: Key.busts)
        self.steals      = defaults.integer(forKey: Key.steals)
        self.biggestKeep = defaults.integer(forKey: Key.biggestKeep)
        self.winStreak   = defaults.integer(forKey: Key.winStreak)
        self.bestStreak  = defaults.integer(forKey: Key.bestStreak)
        if let raw = defaults.dictionary(forKey: Key.faceCounts) as? [String: Int] {
            self.faceCounts = Dictionary(
                uniqueKeysWithValues: raw.compactMap { k, v in
                    Int(k).map { ($0, v) }
                }
            )
        } else {
            self.faceCounts = [:]
        }
        self.gamesByDifficulty = (defaults.dictionary(forKey: Key.gamesByDifficulty) as? [String: Int]) ?? [:]
        self.winsByDifficulty  = (defaults.dictionary(forKey: Key.winsByDifficulty)  as? [String: Int]) ?? [:]
        self.gamesByPace       = (defaults.dictionary(forKey: Key.gamesByPace)       as? [String: Int]) ?? [:]
        self.winsByPace        = (defaults.dictionary(forKey: Key.winsByPace)        as? [String: Int]) ?? [:]
    }

    /// The face most often set aside, or nil if no picks recorded yet.
    var hotFace: Face? {
        guard let topKey = faceCounts.max(by: { $0.value < $1.value })?.key else { return nil }
        return Face(rawValue: topKey)
    }

    /// Win rate as a 0...1 ratio, or nil if no games played.
    var winRate: Double? {
        gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) : nil
    }

    // MARK: - Recording

    func recordBust() {
        busts += 1
    }

    func recordBank(sum: Int, stoleATile: Bool) {
        if sum > biggestKeep { biggestKeep = sum }
        if stoleATile { steals += 1 }
    }

    func recordPicks(_ faces: [Face]) {
        for f in faces {
            faceCounts[f.rawValue, default: 0] += 1
        }
    }

    func recordGameOver(humanWon: Bool, humanScore: Int, difficulty: String, pace: String) {
        gamesPlayed += 1
        if humanScore > bestScore { bestScore = humanScore }
        if humanWon {
            wins += 1
            winStreak += 1
            if winStreak > bestStreak { bestStreak = winStreak }
        } else {
            winStreak = 0
        }
        gamesByDifficulty[difficulty, default: 0] += 1
        if humanWon { winsByDifficulty[difficulty, default: 0] += 1 }
        gamesByPace[pace, default: 0] += 1
        if humanWon { winsByPace[pace, default: 0] += 1 }
    }
}
