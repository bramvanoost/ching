import XCTest
@testable import CHINGEngine

final class EngineStopTests: XCTestCase {

    func testStopBanksWhenInRollPhaseWithSetAside() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .roll
        s.setAside = [.coin, .four, .three]  // sum = 12... too low for a tile
        // Sum 12 < any center tile (smallest is 21), so this should bust.
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [])
        XCTAssertEqual(s2.current, 1)
    }

    func testStopNoopWhenSetAsideEmpty() {
        var rng = Mulberry32(seed: 0)
        let s = initialState(playerIds: ["P0", "P1"])
        // phase already .roll, setAside empty
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2, s)
    }

    func testStopBanksHighestAvailableTile() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .four, .four]  // 5+5+5+4+4 = 23
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [23])
        XCTAssertFalse(s2.centerTiles.contains(23))
        XCTAssertEqual(s2.current, 1)
    }

    func testStopStealsRivalTopTileOnExactMatch() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.players[1].tiles = [25]
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .five, .five]  // sum 25 (coin = 5)
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [25])
        XCTAssertEqual(s2.players[1].tiles, [])
        // The 25 in center is untouched because steal occurred first.
        XCTAssertTrue(s2.centerTiles.contains(25))
    }

    func testStopPrefersStealOverCenterWhenBothPossible() {
        var rng = Mulberry32(seed: 0)
        var s = initialState(playerIds: ["P0", "P1"])
        s.players[1].tiles = [24]
        s.phase = .roll
        s.setAside = [.coin, .coin, .five, .five, .four]  // sum 24
        let s2 = step(state: s, action: .stop, rng: &rng)
        XCTAssertEqual(s2.players[0].tiles, [24])
        XCTAssertEqual(s2.players[1].tiles, [])
        XCTAssertTrue(s2.centerTiles.contains(24))
    }
}
