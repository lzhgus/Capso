import Foundation

/// Remembers the file of the recording in progress so it can be recovered
/// if the app quits before the recording is finalized.
public enum InterruptedRecording {
    static let key = "inProgressRecordingPath"

    static func mark(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.path, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Returns the file left behind by an unfinished recording, if it still
    /// exists, and forgets it so recovery runs at most once.
    public static func take(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}
