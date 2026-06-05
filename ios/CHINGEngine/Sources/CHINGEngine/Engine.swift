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
