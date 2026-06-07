import XCTest
@testable import ShellYesEngine

final class TypesTests: XCTestCase {

    func testRoundTripStateCodable() throws {
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
        XCTAssertEqual(decoded, original)
    }

    func testFaceValueOfCoinIsFive() {
        XCTAssertEqual(Face.coin.value, 5)
        XCTAssertEqual(Face.one.value, 1)
        XCTAssertEqual(Face.five.value, 5)
    }

    func testTileCoinsTiers() {
        XCTAssertEqual(tileCoins(21), 1)
        XCTAssertEqual(tileCoins(24), 1)
        XCTAssertEqual(tileCoins(25), 2)
        XCTAssertEqual(tileCoins(28), 2)
        XCTAssertEqual(tileCoins(29), 3)
        XCTAssertEqual(tileCoins(32), 3)
        XCTAssertEqual(tileCoins(33), 4)
        XCTAssertEqual(tileCoins(36), 4)
    }
}
