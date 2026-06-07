/// A deterministic pseudo-random source returning Doubles in [0, 1).
/// Matches the contract of TS `Rng` from src/engine.ts.
public protocol CHINGRandom {
    mutating func next() -> Double
}

/// Bit-identical port of the mulberry32 PRNG used in sim/regression.ts.
/// Must produce the same sequence as the TS implementation for the same seed,
/// since parity tests rely on this.
public struct Mulberry32: CHINGRandom {
    private var a: UInt32

    public init(seed: UInt32) {
        self.a = seed
    }

    public mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t: UInt32 = a
        t = (t ^ (t &>> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t &>> 7)) &* (t | 61)))
        let result: UInt32 = t ^ (t &>> 14)
        return Double(result) / 4_294_967_296.0
    }
}
