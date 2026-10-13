import Foundation

public enum DiskSpace {
    /// Below this, an active recording is stopped so the file can still be finalized.
    public static let minimumToKeepRecording: Int64 = 1_000_000_000
    /// Below this, the user is warned before a recording starts.
    public static let recommendedToStartRecording: Int64 = 3_000_000_000

    /// Free space usable for important data on the volume containing `url`.
    public static func availableBytes(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}
