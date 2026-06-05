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
    case .pick(let face):
        return applyPick(state, face: face)
    case .stop:
        return state  // implemented in Task 8
    }
}

func applyPick(_ state: State, face: Face) -> State {
    guard state.phase == .pick else { return state }
    guard !state.pickedFaces.contains(face) else { return state }
    let taken = state.rolled.filter { $0 == face }
    guard !taken.isEmpty else { return state }
    var next = state
    next.setAside.append(contentsOf: taken)
    next.pickedFaces.append(face)
    next.diceInHand -= taken.count
    next.rolled = []
    next.phase = .roll
    if next.diceInHand == 0 {
        return tryBank(next)
    }
    return next
}

func tryBank(_ state: State) -> State {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    let hasCoin = state.setAside.contains(.coin)
    guard hasCoin else { return bust(state) }

    // Center: take the highest tile <= sum.
    // (Steal-from-rival branch is added in Task 9.)
    let available = state.centerTiles.filter { $0 <= sum }
    guard !available.isEmpty else { return bust(state) }
    let taken = available.max()!
    var next = state
    next.centerTiles.removeAll { $0 == taken }
    next.players[state.current].tiles.append(taken)
    return endTurn(next)
}

func rollDie<R: CHINGRandom>(rng: inout R) -> Face {
    let n = Int(rng.next() * 6) + 1
    let clamped = max(1, min(6, n))
    return Face(rawValue: clamped)!
}

func applyRoll<R: CHINGRandom>(_ state: State, rng: inout R) -> State {
    guard state.phase == .roll, state.diceInHand > 0 else { return state }
    let rolled = (0..<state.diceInHand).map { _ in rollDie(rng: &rng) }
    let hasNewFace = rolled.contains { !state.pickedFaces.contains($0) }
    if !hasNewFace {
        return bust(state)
    }
    var next = state
    next.rolled = rolled
    next.phase = .pick
    return next
}

func endTurn(_ state: State) -> State {
    if state.centerTiles.isEmpty {
        var s = state
        s.phase = .over
        s.rolled = []
        s.setAside = []
        s.pickedFaces = []
        s.diceInHand = 0
        return s
    }
    var s = state
    s.current = (state.current + 1) % state.players.count
    s.diceInHand = TOTAL_DICE
    s.rolled = []
    s.setAside = []
    s.pickedFaces = []
    s.phase = .roll
    return s
}

func bust(_ state: State) -> State {
    var players = state.players
    var centerTiles = state.centerTiles
    let me = players[state.current]
    if let top = me.tiles.last {
        players[state.current].tiles.removeLast()
        centerTiles.append(top)
        centerTiles.sort()
    }
    // Burn the highest remaining center tile so the supply depletes (CLAUDE.md).
    if !centerTiles.isEmpty {
        centerTiles.removeLast()
    }
    var s = state
    s.players = players
    s.centerTiles = centerTiles
    return endTurn(s)
}
