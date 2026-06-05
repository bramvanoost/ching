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
}
