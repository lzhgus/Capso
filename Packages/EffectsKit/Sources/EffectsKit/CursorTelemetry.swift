// Packages/EffectsKit/Sources/EffectsKit/CursorTelemetry.swift

@preconcurrency import Foundation
import CoreGraphics
import AppKit

/// Records cursor movement and click events during a screen recording session.
///
/// Events are captured via a CGEvent tap on a dedicated background thread and
/// stored as normalized coordinates relative to the recording area. The data can
/// be exported and serialized to JSON for post-processing in the recording editor.
///
/// - Note: `CursorTelemetry` is separate from `ClickMonitor` by design.
///   `ClickMonitor` drives real-time visual effects during recording; `CursorTelemetry`
///   accumulates data for offline editor use.
public final class CursorTelemetry: @unchecked Sendable {

    // MARK: - Private state

    private let recordingRect: CGRect
    private let lock = NSLock()
    private var events: [CursorEvent] = []

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var tapThread: Thread?
    private var watchdogTimer: DispatchSourceTimer?
    private var receivedEventCount: Int = 0

    // NSEvent monitors — captured separately from the CGEventTap so we still
    // get telemetry when the HID tap is disabled (e.g. by Secure Input mode
    // which macOS enables when a Terminal password prompt is focused).
    private var globalNSMonitor: Any?
    private var localNSMonitor: Any?
    private var nsEventCount: Int = 0

    // MARK: - Debug log file

    private static let debugLogURL: URL = URL(fileURLWithPath: "/tmp/capso-telemetry.log")

    private static func debugLog(_ message: String) {
        let ts = Date().ISO8601Format()
        let line = "[\(ts)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: debugLogURL.path) {
            if let handle = try? FileHandle(forWritingTo: debugLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: debugLogURL)
        }
    }

    /// Opaque pointer produced by `Unmanaged.passRetained(self)` in `start()`.
    /// Stored here so both `stop()` and `deinit` can release it exactly once.
    private var selfRetainPointer: UnsafeMutableRawPointer?

    /// System uptime at the moment `start()` was called; used to produce
    /// recording-relative timestamps.
    private var startTime: TimeInterval = 0

    // MARK: - Init

    /// Creates a new telemetry recorder for the given recording area.
    /// - Parameter recordingRect: The region being recorded, in global display coordinates
    ///   (flipped or un-flipped — must match the coordinate system of the CGEvent location
    ///   values that will be reported by the event tap on the target display).
    public init(recordingRect: CGRect) {
        self.recordingRect = recordingRect
    }

    // MARK: - Coordinate normalization

    /// Returns true when `globalPoint` falls within `recordingRect` (inclusive
    /// of the edges). Used to skip recording events when the cursor leaves
    /// the captured region — otherwise we'd clamp to an edge and the overlay
    /// at playback would appear pinned to the boundary even when the real
    /// cursor had clearly moved away to a different app/screen.
    public func isInsideRecordingRect(_ globalPoint: CGPoint) -> Bool {
        let x = Double(globalPoint.x)
        let y = Double(globalPoint.y)
        return x >= recordingRect.minX && x <= recordingRect.maxX
            && y >= recordingRect.minY && y <= recordingRect.maxY
    }

    /// Converts a global display point to normalized coordinates [0, 1] clamped to the
    /// recording area.
    ///
    /// - Parameter globalPoint: A point in global display coordinates.
    /// - Returns: `(x, y)` in [0, 1] × [0, 1], clamped if the point is outside the rect.
    public func normalize(globalPoint: CGPoint) -> (x: Double, y: Double) {
        let w = recordingRect.width
        let h = recordingRect.height

        guard w > 0, h > 0 else { return (0, 0) }

        let rawX = (globalPoint.x - recordingRect.minX) / w
        let rawY = (globalPoint.y - recordingRect.minY) / h

        let clampedX = min(max(Double(rawX), 0.0), 1.0)
        let clampedY = min(max(Double(rawY), 0.0), 1.0)
        return (clampedX, clampedY)
    }

    // MARK: - Manual event injection (primarily for testing)

    /// Appends an event directly. Use this for testing or synthetic event injection.
    /// The coordinates are normalized and clamped relative to the recording area.
    public func addEvent(timestamp: TimeInterval, globalPoint: CGPoint, type: CursorEventType) {
        let (nx, ny) = normalize(globalPoint: globalPoint)
        let event = CursorEvent(timestamp: timestamp, x: nx, y: ny, type: type)
        lock.withLock { events.append(event) }
    }

    // MARK: - CGEvent tap lifecycle

    /// Starts capturing cursor events via a CGEvent tap on a background thread.
    ///
    /// Captures: `.mouseMoved`, `.leftMouseDragged`, `.rightMouseDragged`,
    /// `.scrollWheel`, `.leftMouseDown`, `.rightMouseDown`.
    /// The tap runs in listen-only mode (`.listenOnly`) at `.cghidEventTap`.
    ///
    /// A `DispatchSemaphore` ensures the background run-loop is up and `runLoop`
    /// is stored before this method returns, eliminating the race window between
    /// `start()` and `stop()`.
    public func start() {
        guard eventTap == nil else { return }

        // Reset the debug log at the start of each recording so the file
        // reflects the current session.
        try? FileManager.default.removeItem(at: Self.debugLogURL)
        Self.debugLog("start() called; recordingRect=\(recordingRect)")

        // Record the reference time for relative timestamps.
        startTime = ProcessInfo.processInfo.systemUptime
        receivedEventCount = 0

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // Retain self so the C callback can reach it. Store the opaque pointer
        // so we can release it exactly once from stop() or deinit.
        let userInfo = Unmanaged.passRetained(self).toOpaque()
        selfRetainPointer = userInfo

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let telemetry = Unmanaged<CursorTelemetry>.fromOpaque(userInfo).takeUnretainedValue()

                // If the system disabled the tap (callback took too long, or
                // a user-input issue), re-enable it so subsequent events flow.
                // Without this, a single timeout kills all capture for the
                // rest of the recording.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    CursorTelemetry.debugLog("CALLBACK: tap disabled (type=\(type.rawValue)); re-enabling")
                    if let t = telemetry.eventTap {
                        CGEvent.tapEnable(tap: t, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                telemetry.handleCGEvent(type: type, event: event)
                telemetry.receivedEventCount &+= 1
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            // tapCreate failed; release the retained self to avoid leak.
            Unmanaged<CursorTelemetry>.fromOpaque(userInfo).release()
            selfRetainPointer = nil
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        // Semaphore ensures the background thread has stored `runLoop` in the
        // lock-protected property before `start()` returns, so `stop()` cannot
        // observe a nil runLoop after `start()` has been called.
        let readySemaphore = DispatchSemaphore(value: 0)

        let bgThread = Thread { [weak self] in
            guard let source, let self else { return }
            let rl = CFRunLoopGetCurrent()
            self.lock.withLock { self.runLoop = rl }
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            readySemaphore.signal()
            CFRunLoopRun()
        }
        bgThread.name = "com.capso.cursortelemetry"
        bgThread.qualityOfService = .userInteractive
        bgThread.start()
        tapThread = bgThread

        // Block until the run loop is running and `runLoop` is set.
        readySemaphore.wait()

        Self.debugLog("tap created and enabled; bg thread running")

        // Watchdog: periodically report the event count and check that the
        // tap is still enabled; re-enable if macOS silently disabled it.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        var lastTapCount = 0
        var lastNSCount = 0
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let tapCount = self.receivedEventCount
            let nsCount = self.nsEventCount
            let tapDelta = tapCount - lastTapCount
            let nsDelta = nsCount - lastNSCount
            lastTapCount = tapCount
            lastNSCount = nsCount
            let tapAlive: String
            if let t = self.eventTap {
                let enabled = CGEvent.tapIsEnabled(tap: t)
                tapAlive = enabled ? "enabled" : "DISABLED"
                if !enabled {
                    CursorTelemetry.debugLog("WATCHDOG: tap disabled; re-enabling")
                    CGEvent.tapEnable(tap: t, enable: true)
                }
            } else {
                tapAlive = "tap=nil"
            }
            CursorTelemetry.debugLog(
                "heartbeat: tap=(total=\(tapCount) delta=\(tapDelta) \(tapAlive)) ns=(total=\(nsCount) delta=\(nsDelta))"
            )
        }
        timer.resume()
        watchdogTimer = timer

        // Parallel capture path via NSEvent monitors — NSEvent uses a
        // different delivery mechanism than CGEventTap and is NOT killed
        // by Secure Input or tap-timeout. If the tap dies, these keep the
        // telemetry flowing.
        installNSEventMonitors()
    }

    private func installNSEventMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown,
            .scrollWheel,
        ]

        let handler: (NSEvent) -> Void = { [weak self] ns in
            guard let self else { return }
            self.handleNSEvent(ns)
        }

        globalNSMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        // Local monitor so we also see events when Capso is frontmost.
        localNSMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { ns in
            handler(ns)
            return ns
        }
        Self.debugLog("NSEvent global+local monitors installed")
    }

    private func handleNSEvent(_ ns: NSEvent) {
        // Prefer the event's own cgEvent.location — that's already in global
        // CG top-left coords (matching recordingRect) and reflects the cursor
        // position AT THE TIME of the event, not the current cursor position.
        // Fall back to a manual AppKit→CG conversion if somehow unavailable.
        let cgPoint: CGPoint
        if let cge = ns.cgEvent {
            cgPoint = cge.location
        } else {
            let ap = NSEvent.mouseLocation
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            cgPoint = CGPoint(x: ap.x, y: primaryHeight - ap.y)
        }

        // Cursor was outside the capture region — skip, otherwise clamping
        // to an edge makes the overlay "jump" to a boundary during playback.
        guard isInsideRecordingRect(cgPoint) else { return }

        let eventType: CursorEventType
        switch ns.type {
        case .leftMouseDown:  eventType = .leftClick
        case .rightMouseDown: eventType = .rightClick
        default:              eventType = .move
        }

        let timestamp = ProcessInfo.processInfo.systemUptime - startTime
        let (nx, ny) = normalize(globalPoint: cgPoint)
        let cursorEvent = CursorEvent(timestamp: timestamp, x: nx, y: ny, type: eventType)
        lock.withLock { events.append(cursorEvent) }
        nsEventCount &+= 1
    }

    /// Stops the event tap and releases the retained self reference taken in `start()`.
    public func stop() {
        Self.debugLog("stop() called; tap_total=\(receivedEventCount) ns_total=\(nsEventCount)")
        watchdogTimer?.cancel()
        watchdogTimer = nil

        if let g = globalNSMonitor { NSEvent.removeMonitor(g) }
        if let l = localNSMonitor { NSEvent.removeMonitor(l) }
        globalNSMonitor = nil
        localNSMonitor = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        // Access runLoop under the lock to avoid a data race with the background thread.
        let rl = lock.withLock { runLoop }
        if let rl { CFRunLoopStop(rl) }

        // Release the retain taken in start() — guarded to only happen once.
        if let ptr = selfRetainPointer {
            Unmanaged<CursorTelemetry>.fromOpaque(ptr).release()
            selfRetainPointer = nil
        }

        eventTap = nil
        runLoopSource = nil
        lock.withLock { runLoop = nil }
        tapThread = nil
    }

    // MARK: - Export & persistence

    /// Returns a snapshot of all events collected so far, thread-safely.
    public func exportData() -> CursorTelemetryData {
        let snapshot = lock.withLock { events }
        return CursorTelemetryData(
            recordingAreaWidth: Double(recordingRect.width),
            recordingAreaHeight: Double(recordingRect.height),
            events: snapshot
        )
    }

    /// Encodes the telemetry data as JSON and writes it to the given URL.
    public func save(to url: URL) throws {
        let data = exportData()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url, options: .atomic)
    }

    /// Reads and decodes `CursorTelemetryData` from a JSON file.
    public static func load(from url: URL) throws -> CursorTelemetryData {
        let jsonData = try Data(contentsOf: url)
        return try JSONDecoder().decode(CursorTelemetryData.self, from: jsonData)
    }

    // MARK: - Private helpers

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let location = event.location
        let point = CGPoint(x: location.x, y: location.y)

        // Cursor outside the captured region — skip, same rationale as
        // handleNSEvent (avoid edge-clamped positions in telemetry).
        guard isInsideRecordingRect(point) else { return }

        // Timestamp is relative to when start() was called, not absolute uptime.
        let timestamp = ProcessInfo.processInfo.systemUptime - startTime

        let eventType: CursorEventType
        switch type {
        case .leftMouseDown:
            eventType = .leftClick
        case .rightMouseDown:
            eventType = .rightClick
        default:
            eventType = .move
        }

        let (nx, ny) = normalize(globalPoint: point)
        let cursorEvent = CursorEvent(timestamp: timestamp, x: nx, y: ny, type: eventType)
        lock.withLock { events.append(cursorEvent) }
    }

    // MARK: - Deinit

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        // Use the lock-protected accessor to avoid reading runLoop on an arbitrary thread.
        let rl = lock.withLock { runLoop }
        if let rl { CFRunLoopStop(rl) }

        // Release the retain taken in start() if stop() was never called.
        if let ptr = selfRetainPointer {
            Unmanaged<CursorTelemetry>.fromOpaque(ptr).release()
            selfRetainPointer = nil
        }
    }
}
