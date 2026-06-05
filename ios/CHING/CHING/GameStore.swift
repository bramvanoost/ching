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

    private static let difficultyKey = "ching.difficulty"

    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
    }

    init(seed: UInt32) {
        self.rng = Mulberry32(seed: seed)
        self.state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
        let raw = UserDefaults.standard.string(forKey: Self.difficultyKey) ?? ""
        self.difficulty = Difficulty(rawValue: raw) ?? .normal
    }

    convenience init() {
        self.init(seed: UInt32.random(in: 1...UInt32.max))
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
                return "STEAL FROM \(state.players[i].id)"
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
        let adjusted = max(0, min(1, base + difficulty.modifier))
        return CHINGEngine.Difficulty(discipline: adjusted)
    }

    func apply(_ action: Action) {
        state = step(state: state, action: action, rng: &rng)
    }

    func runAIIfNeeded() {
        while !isOver, let ai = currentAIDifficulty {
            let action = decide(state: state, ai: ai)
            apply(action)
        }
    }

    func newGame() {
        rng = Mulberry32(seed: UInt32.random(in: 1...UInt32.max))
        state = initialState(playerIds: ["YOU", "JONES", "BOT 03"])
    }
}
