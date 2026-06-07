import XCTest
@testable import CHINGEngine

final class EngineInitTests: XCTestCase {

    func testInitialStateForTwoPlayers() {
        let s = initialState(playerIds: ["P0", "P1"])
        XCTAssertEqual(s.players.count, 2)
        XCTAssertEqual(s.players[0].id, "P0")
        XCTAssertTrue(s.players[1].tiles.isEmpty)
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.centerTiles, Array(21...36))
        XCTAssertEqual(s.diceInHand, 8)
        XCTAssertTrue(s.rolled.isEmpty)
        XCTAssertTrue(s.setAside.isEmpty)
        XCTAssertTrue(s.pickedFaces.isEmpty)
        XCTAssertEqual(s.phase, .roll)
    }

    func testScoreSumsTileCoinsPerPlayer() {
        let s = State(
            players: [
                Player(id: "P0", tiles: [22, 28, 33]),  // 1 + 2 + 4 = 7
                Player(id: "P1", tiles: [25, 36]),       // 2 + 4 = 6
            ],
            current: 0, centerTiles: [], diceInHand: 8,
            rolled: [], setAside: [], pickedFaces: [], phase: .roll
        )
        XCTAssertEqual(score(s), [7, 6])
    }
}
