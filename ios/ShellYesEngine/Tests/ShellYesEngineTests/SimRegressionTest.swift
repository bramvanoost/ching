import XCTest
@testable import CHINGEngine

final class SimRegressionTest: XCTestCase {

    func testHigherDisciplineBeatsLowerOver200Games() {
        let GAMES = 200
        let DISC_LOW = 0.2
        let DISC_HIGH = 0.8
        let MAX_STEPS = 50_000

        var lowWins = 0
        var highWins = 0
        var ties = 0

        for g in 0..<GAMES {
            var rng = Mulberry32(seed: UInt32(g + 1))
            // Alternate seats so first-mover advantage doesn't skew the result.
            let playerDisc: [Double] = g % 2 == 0
                ? [DISC_LOW, DISC_HIGH]
                : [DISC_HIGH, DISC_LOW]
            var state = initialState(playerIds: ["P0", "P1"])
            var steps = 0
            while state.phase != .over {
                steps += 1
                XCTAssertLessThan(steps, MAX_STEPS, "game \(g) did not terminate")
                if steps >= MAX_STEPS { break }
                let ai = Difficulty(discipline: playerDisc[state.current])
                state = step(state: state, action: decide(state: state, ai: ai), rng: &rng)
            }
            let scores = score(state)
            let lowScore = playerDisc[0] == DISC_LOW ? scores[0] : scores[1]
            let highScore = playerDisc[0] == DISC_LOW ? scores[1] : scores[0]
            if highScore > lowScore {
                highWins += 1
            } else if lowScore > highScore {
                lowWins += 1
            } else {
                ties += 1
            }
        }

        XCTAssertGreaterThan(
            highWins, lowWins,
            "higher discipline (\(highWins)) did not beat lower (\(lowWins)), ties=\(ties)"
        )
    }
}
