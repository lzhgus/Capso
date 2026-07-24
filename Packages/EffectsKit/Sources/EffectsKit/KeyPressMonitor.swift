import AppKit
import CoreGraphics

/// Monitors global keyboard events during screen recording and emits
/// KeyCastr-style display strings for each key-down.
///
/// Capture strategy (KeyCastr `KCEventTap` + Capso click-monitor lessons):
/// 1. Prefer a **listen-only** `CGEventTap` at the session level (same as KeyCastr)
/// 2. Re-enable the tap if macOS disables it (`tapDisabledByTimeout` / user input)
/// 3. Fall back to `NSEvent` global+local monitors if the tap cannot be created
///
/// KeyCastr is BSD-3-Clause; see `KeystrokeFormatter` and `THIRD_PARTY_NOTICES.md`.
public final class KeyPressMonitor: @unchecked Sendable {
    public var onKeyDisplay: (@Sendable (String) -> Void)?
    /// Emits `true` for command-ish keystrokes (⌘/⌃) so the UI can break bezel lines.
    public var onKeyDisplayDetailed: (@Sendable (_ label: String, _ isCommand: Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var useEventTap = false

    public init() {}

    public func start() {
        guard eventTap == nil, globalMonitor == nil, localMonitor == nil else { return }
        if installEventTap() {
            useEventTap = true
            return
        }
        useEventTap = false
        installNSEventMonitors()
    }

    public func stop() {
        removeEventTap()
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    deinit {
        // Best-effort cleanup off-main.
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    // MARK: - CGEventTap (KeyCastr path)

    private func installEventTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyPressMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleTap(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func handleTap(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // KeyCastr returns the event unchanged (listen-only).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if let nsEvent = NSEvent(cgEvent: event) {
                emit(from: nsEvent)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - NSEvent fallback

    private func installNSEventMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.emit(from: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.emit(from: event)
            return event
        }
    }

    private func emit(from event: NSEvent) {
        // Use the NSEvent overload so autorepeats (`isARepeat`) are dropped —
        // the Keystroke-only path has no repeat flag and would flood the bezel.
        guard let label = KeystrokeFormatter.displayString(for: event) else { return }
        let keystroke = KeystrokeFormatter.Keystroke(event: event)
        onKeyDisplayDetailed?(label, keystroke.isCommand)
        onKeyDisplay?(label)
    }
}
