import Foundation

private func capsoUncaughtExceptionHandler(_ exception: NSException) {
    guard UserDefaults.standard.object(forKey: "diagnosticLoggingEnabled") as? Bool ?? false else {
        return
    }

    DiagnosticLogger.append(
        """
        Uncaught NSException
        name=\(exception.name.rawValue)
        reason=\(exception.reason ?? "nil")
        callStack=\(exception.callStackSymbols.joined(separator: "\n"))
        """,
        category: "Crash"
    )
}

public enum DiagnosticLogger {
    public static let maxLogBytes = 1_000_000

    private static let queue = DispatchQueue(label: "com.awesomemacapps.capso.diagnostic-logger")

    public static var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.awesomemacapps.capso", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    public static var logFileURL: URL {
        logDirectory.appendingPathComponent("capso.log")
    }

    public static var diagnosticReportDirectories: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true),
        ]
    }

    public static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler(capsoUncaughtExceptionHandler)
    }

    public static func append(
        _ message: String,
        category: String = "App",
        fileURL: URL = DiagnosticLogger.logFileURL
    ) {
        queue.sync {
            let line = "\(timestamp()) [\(category)] \(message)\n"
            write(line, to: fileURL)
        }
    }

    public static func append(
        error: Error,
        context: String,
        category: String = "Error",
        fileURL: URL = DiagnosticLogger.logFileURL
    ) {
        append("\(context): \(error.localizedDescription)", category: category, fileURL: fileURL)
    }

    @discardableResult
    public static func prepareLogFile(at fileURL: URL = DiagnosticLogger.logFileURL) -> URL {
        queue.sync {
            let fm = FileManager.default
            do {
                try fm.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fm.fileExists(atPath: fileURL.path) {
                    try Data().write(to: fileURL, options: [.atomic])
                }
            } catch {
                // Diagnostic helpers must never affect app behavior.
            }
            return fileURL
        }
    }

    public static func recentCrashReportURLs(limit: Int = 10) -> [URL] {
        let fm = FileManager.default
        let matches = diagnosticReportDirectories.flatMap { directory -> [URL] in
            guard let urls = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return urls.filter { url in
                let name = url.lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                return (name.contains("capso") || name.contains("com.awesomemacapps.capso"))
                    && ["crash", "ips", "diag"].contains(ext)
            }
        }

        return matches.sorted { lhs, rhs in
            modificationDate(lhs) > modificationDate(rhs)
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func write(_ line: String, to fileURL: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            rotateIfNeeded(fileURL: fileURL)
            let data = Data(line.utf8)
            if fm.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: [.atomic])
            }
        } catch {
            // Diagnostic logging must never affect app behavior.
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func rotateIfNeeded(fileURL: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxLogBytes else {
            return
        }

        let rotated = fileURL.deletingPathExtension()
            .appendingPathExtension("old")
            .appendingPathExtension(fileURL.pathExtension)
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: fileURL, to: rotated)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
