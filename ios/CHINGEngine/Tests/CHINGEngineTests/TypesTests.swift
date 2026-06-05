import Testing
import Foundation
@testable import CHINGEngine

@Test
func roundTripStateCodable() throws {
    let original = State(
        players: [
            Player(id: "P0", tiles: [22, 28]),
            Player(id: "P1", tiles: []),
        ],
        current: 0,
        centerTiles: [21, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 36],
        diceInHand: 5,
        rolled: [.three, .three, .five, .coin, .one],
        setAside: [.two, .two, .four],
        pickedFaces: [.two, .four],
        phase: .pick
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(State.self, from: data)
    #expect(decoded == original)
}

@Test
func faceValueOfCoinIsFive() {
    #expect(Face.coin.value == 5)
    #expect(Face.one.value == 1)
    #expect(Face.five.value == 5)
}

@Test
func tileCoinsTiers() {
    #expect(tileCoins(21) == 1)
    #expect(tileCoins(24) == 1)
    #expect(tileCoins(25) == 2)
    #expect(tileCoins(28) == 2)
    #expect(tileCoins(29) == 3)
    #expect(tileCoins(32) == 3)
    #expect(tileCoins(33) == 4)
    #expect(tileCoins(36) == 4)
}
