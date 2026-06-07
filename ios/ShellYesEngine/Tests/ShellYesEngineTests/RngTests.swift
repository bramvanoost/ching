import XCTest
@testable import CHINGEngine

final class RngTests: XCTestCase {

    func testMulberry32MatchesTsForSeed1() {
        var rng = Mulberry32(seed: 1)
        let expected: [Double] = [
            0.6270739405881613,
            0.002735721180215478,
            0.5274470399599522,
            0.9810509674716741,
            0.9683778982143849,
            0.281103502959013,
            0.6128388606011868,
            0.7207431411370635,
            0.425796952098608,
            0.9948229456786066,
        ]
        for (i, value) in expected.enumerated() {
            let actual = rng.next()
            XCTAssertEqual(actual, value, "mulberry32 drift at seed=1, index \(i)")
        }
    }

    func testMulberry32SequenceIsRepeatable() {
        var a = Mulberry32(seed: 42)
        var b = Mulberry32(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }
}
