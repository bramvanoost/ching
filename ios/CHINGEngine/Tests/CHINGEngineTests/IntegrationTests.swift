import XCTest
@testable import CHINGEngine

final class IntegrationTests: XCTestCase {

    func testAiVsAiGameTerminates() {
        var rng = Mulberry32(seed: 1)
        var state = initialState(playerIds: ["P0", "P1"])
        let lowDisc = Difficulty(discipline: 0.2)
        let highDisc = Difficulty(discipline: 0.8)
        var steps = 0
        let MAX_STEPS = 5000
        while state.phase != .over {
            steps += 1
            XCTAssertLessThan(steps, MAX_STEPS, "game did not terminate in \(MAX_STEPS) steps")
            if steps >= MAX_STEPS { break }
            let ai = state.current == 0 ? lowDisc : highDisc
            let action = decide(state: state, ai: ai)
            state = step(state: state, action: action, rng: &rng)
        }
        XCTAssertEqual(state.phase, .over)
        XCTAssertTrue(state.centerTiles.isEmpty)
    }
}
