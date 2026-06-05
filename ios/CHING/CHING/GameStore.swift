import Foundation
import Observation
import CHINGEngine

@MainActor
@Observable
final class GameStore {
    static let humanSeat = 0
    static let aiSeat = 1

    private(set) var state: State
    private var rng: Mulberry32

    private let aiDifficulty = Difficulty(discipline: 0.30)

    init(seed: UInt32) {
        self.rng = Mulberry32(seed: seed)
        self.state = initialState(playerIds: ["YOU", "JONES"])
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

    func canPick(_ face: Face) -> Bool {
        state.phase == .pick &&
            isHumanTurn &&
            !state.pickedFaces.contains(face) &&
            state.rolled.contains(face)
    }

    func apply(_ action: Action) {
        state = step(state: state, action: action, rng: &rng)
    }

    func runAIIfNeeded() {
        while !isOver && !isHumanTurn {
            let action = decide(state: state, ai: aiDifficulty)
            apply(action)
        }
    }

    func newGame() {
        rng = Mulberry32(seed: UInt32.random(in: 1...UInt32.max))
        state = initialState(playerIds: ["YOU", "JONES"])
    }
}
