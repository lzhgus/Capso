// Packages/EffectsKit/Sources/EffectsKit/ClickMonitor.swift
import AppKit
import CoreGraphics

/// Monitors global mouse clicks during screen recording, reporting each
/// click position in global CG top-left coordinates (the space the rest
/// of the click-highlight pipeline expects — see
/// `ClickHighlightWindow.showClick`).
///
/// ## Implementation history
///
/// An earlier implementation used `CGEvent.tapCreate` at the HID layer.
/// That path is fragile:
///
///   * `tapDisabledByTimeout` — macOS disables the tap if any single
///     callback exceeds the deadline. Once disabled, no more events flow
///     for the rest of the session.
///   * `tapDisabledByUserInput` — macOS disables the tap whenever
///     Secure Input engages (password fields, Terminal focus, some
///     browser text inputs). Very common during actual recordings.
///
/// The symptom was "the first click shows a highlight ring, but every
/// click after that silently does nothing" — because the tap had died
/// after the first event. `CursorTelemetry` works around this with a
/// watchdog timer + an NSEvent fallback path; click-highlight doesn't
/// need that complexity because the fallback path alone is sufficient.
///
/// ## Current implementation: NSEvent monitors
///
/// `addGlobalMonitorForEvents` receives events posted to other apps
/// (the common case: user is in Figma / VS Code / a browser).
/// `addLocalMonitorForEvents` receives events posted to Capso itself
/// (rare during recording but covers the corner case). The two are
/// mutually exclusive per Apple's docs — no duplicate delivery.
///
/// NSEvent monitors are delivered through AppKit, not the HID tap, so
/// they are NOT killed by Secure Input. They require the same
/// Accessibility permission the app already holds for CGEventTap usage
/// elsewhere (e.g. `CursorTelemetry`).
public final class ClickMonitor: @unchecked Sendable {
    public var onClick: (@Sendable (CGPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

    public func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event // pass through so the app still processes the click normally
        }
    }

    public func stop() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        // Prefer `cgEvent.location` — that's already in global CG top-left
        // coords, which is what `ClickHighlightWindow.showClick(at:)`
        // expects. NSEvent's own `locationInWindow` is in flipped AppKit
        // coords tied to a window, which would require manual conversion.
        if let location = event.cgEvent?.location {
            onClick?(location)
        }
    }

    deinit {
        // Deinit can run on any thread; NSEvent.removeMonitor is safe off-main.
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
