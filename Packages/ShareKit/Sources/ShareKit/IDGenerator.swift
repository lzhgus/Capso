// Packages/ShareKit/Sources/ShareKit/IDGenerator.swift

public enum IDGenerator {
    private static let charset: [Character] = Array("0123456789abcdefghijklmnopqrstuv")

    /// 7-char base32 ID. ~34B keyspace; collision probability over 1M IDs is ~14ppm.
    public static func shortID() -> String {
        var rng = SystemRandomNumberGenerator()
        var result = ""
        result.reserveCapacity(7)
        for _ in 0..<7 {
            let idx = Int(rng.next(upperBound: UInt32(charset.count)))
            result.append(charset[idx])
        }
        return result
    }
}
