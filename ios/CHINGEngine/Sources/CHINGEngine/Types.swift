public enum Face: Int, Codable, Sendable, CaseIterable, Equatable {
    case one = 1, two = 2, three = 3, four = 4, five = 5, coin = 6

    public var value: Int {
        self == .coin ? 5 : rawValue
    }
}

public enum Phase: String, Codable, Sendable, Equatable {
    case roll, pick, over
}

public struct Player: Codable, Sendable, Equatable {
    public var id: String
    public var tiles: [Int]

    public init(id: String, tiles: [Int]) {
        self.id = id
        self.tiles = tiles
    }
}

public struct State: Codable, Sendable, Equatable {
    public var players: [Player]
    public var current: Int
    public var centerTiles: [Int]
    public var diceInHand: Int
    public var rolled: [Face]
    public var setAside: [Face]
    public var pickedFaces: [Face]
    public var phase: Phase

    public init(
        players: [Player],
        current: Int,
        centerTiles: [Int],
        diceInHand: Int,
        rolled: [Face],
        setAside: [Face],
        pickedFaces: [Face],
        phase: Phase
    ) {
        self.players = players
        self.current = current
        self.centerTiles = centerTiles
        self.diceInHand = diceInHand
        self.rolled = rolled
        self.setAside = setAside
        self.pickedFaces = pickedFaces
        self.phase = phase
    }
}

public enum Action: Codable, Sendable, Equatable {
    case roll
    case pick(face: Face)
    case stop
}

public let TOTAL_DICE = 8

public func tileCoins(_ tile: Int) -> Int {
    if tile <= 24 { return 1 }
    if tile <= 28 { return 2 }
    if tile <= 32 { return 3 }
    return 4
}
