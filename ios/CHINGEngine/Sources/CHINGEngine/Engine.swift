import Foundation

public func initialState(playerIds: [String]) -> State {
    State(
        players: playerIds.map { Player(id: $0, tiles: []) },
        current: 0,
        centerTiles: Array(21...36),
        diceInHand: TOTAL_DICE,
        rolled: [],
        setAside: [],
        pickedFaces: [],
        phase: .roll
    )
}

public func score(_ state: State) -> [Int] {
    state.players.map { $0.tiles.reduce(0) { $0 + tileCoins($1) } }
}

public func step<R: CHINGRandom>(state: State, action: Action, rng: inout R) -> State {
    if state.phase == .over { return state }
    switch action {
    case .roll:
        return applyRoll(state, rng: &rng)
    case .pick:
        return state  // implemented in Task 7
    case .stop:
        return state  // implemented in Task 8
    }
}

func rollDie<R: CHINGRandom>(rng: inout R) -> Face {
    let n = Int(rng.next() * 6) + 1
    let clamped = max(1, min(6, n))
    return Face(rawValue: clamped)!
}

func applyRoll<R: CHINGRandom>(_ state: State, rng: inout R) -> State {
    guard state.phase == .roll, state.diceInHand > 0 else { return state }
    let rolled = (0..<state.diceInHand).map { _ in rollDie(rng: &rng) }
    // Bust-on-no-new-face branch is added in Task 6.
    var next = state
    next.rolled = rolled
    next.phase = .pick
    return next
}
