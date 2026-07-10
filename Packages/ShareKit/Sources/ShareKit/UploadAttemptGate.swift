/// Prevents the same UI surface from starting overlapping upload attempts.
public struct UploadAttemptGate: Sendable {
    private var isInFlight = false

    public init() {}

    public mutating func begin() -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    public mutating func finish() {
        isInFlight = false
    }
}
