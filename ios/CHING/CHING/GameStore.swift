import Foundation
import Observation
import CHINGEngine

enum Difficulty: String, Codable, CaseIterable {
    case easy, normal, hard

    var modifier: Double {
        switch self {
        case .easy: return -0.15
        case .normal: return 0
        case .hard: return 0.15
        }
    }
}

@MainActor
@Observable
final class GameStore {
    static let humanSeat = 0
    static let jonesSeat = 1
    static let bot03Seat = 2

    private let baseDiscipline: [Int: Double] = [
        jonesSeat: 0.30,
        bot03Seat: 0.85,
    ]

    private(set) var state: State
    private var rng: Mulberry32
    private let settings: SettingsStore

    init(seed: UInt32, settings: SettingsStore) {
        self.rng = Mulberry32(seed: seed)
        self.settings = settings
        self.state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
    }

    convenience init(settings: SettingsStore) {
        self.init(seed: UInt32.random(in: 1...UInt32.max), settings: settings)
    }

    var scores: [Int] { score(state) }
    var setAsideSum: Int { state.setAside.reduce(0) { $0 + $1.value } }
    var isHumanTurn: Bool { state.current == Self.humanSeat }
    var isOver: Bool { state.phase == .over }

    var canRoll: Bool {
        state.phase == .roll && state.diceInHand > 0 && isHumanTurn
    }

    var canBank: Bool {
        state.phase == .roll && !state.setAside.isEmpty && isHumanTurn
    }

    var bankActionLabel: String {
        guard canBank else { return "Bank" }
        for i in state.players.indices where i != state.current {
            if let top = state.players[i].tiles.last, top == setAsideSum {
                let name = state.players[i].id.capitalized
                return "Steal \(name)'s safe"
            }
        }
        return "Bank"
    }

    func canPick(_ face: Face) -> Bool {
        state.phase == .pick &&
            isHumanTurn &&
            !state.pickedFaces.contains(face) &&
            state.rolled.contains(face)
    }

    var currentAIDifficulty: CHINGEngine.Difficulty? {
        guard !isHumanTurn else { return nil }
        let base = baseDiscipline[state.current] ?? 0.5
        let adjusted = max(0, min(1, base + settings.difficulty.modifier))
        return CHINGEngine.Difficulty(discipline: adjusted)
    }

    func apply(_ action: Action) {
        state = step(state: state, action: action, rng: &rng)
    }

    private static let aiPaceNanoseconds: UInt64 = 300_000_000

    func runAIIfNeeded(reduceMotion: Bool) async {
        while !isOver, let ai = currentAIDifficulty {
            let action = decide(state: state, ai: ai)
            apply(action)
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: Self.aiPaceNanoseconds)
            }
        }
    }

    func newGame() {
        rng = Mulberry32(seed: UInt32.random(in: 1...UInt32.max))
        state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
    }

    #if DEBUG
    func setStateForTesting(_ s: State) {
        self.state = s
    }
    #endif
}
