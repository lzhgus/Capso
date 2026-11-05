// App/Sources/Capture/EscapeKeyPressSwallower.swift
import AppKit
import Carbon.HIToolbox

/// Decides which key events belong to an Escape press that has already been
/// handled, so the rest of that press can be dropped.
struct EscapeKeyPressFilter: Equatable {
    static let escapeKeyCode = UInt16(kVK_Escape)

    private(set) var isArmed = false

    /// Starts swallowing the press whose first keyDown was just handled.
    mutating func arm() {
        isArmed = true
    }

    mutating func disarm() {
        isArmed = false
    }

    /// Returns `true` when the event is an autorepeat or the release of the
    /// handled press. A fresh Escape press ends swallowing and is let through;
    /// other keys are never touched.
    mutating func shouldSwallow(isKeyDown: Bool, keyCode: UInt16, isRepeat: Bool) -> Bool {
        guard isArmed, keyCode == Self.escapeKeyCode else { return false }
        if isKeyDown {
            guard isRepeat else {
                isArmed = false
                return false
            }
            return true
        }
        isArmed = false
        return true
    }
}

/// Drops the rest of an Escape press after a capture overlay closes on it.
///
/// The autorepeats and the keyUp of that press keep coming to Capso after the
/// overlay is gone. With no Capso window key (or with an unrelated one, such
/// as Settings), AppKit answers each unhandled keyDown with the system alert
/// sound, so holding Escape beeped repeatedly (#356).
@MainActor
final class EscapeKeyPressSwallower {
    static let shared = EscapeKeyPressSwallower()

    /// How often to check whether Escape is still held, in case the keyUp is
    /// delivered somewhere else and never reaches Capso.
    private static let releaseCheckInterval: TimeInterval = 1

    private var filter = EscapeKeyPressFilter()
    private var monitor: Any?
    private var releaseCheck: DispatchWorkItem?
    private let isEscapeKeyDown: () -> Bool

    init(isEscapeKeyDown: @escaping () -> Bool = {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape))
    }) {
        self.isEscapeKeyDown = isEscapeKeyDown
    }

    var isSwallowing: Bool { filter.isArmed }

    /// Call when `event` is the Escape keyDown that closed an overlay.
    /// Anything else is ignored.
    func swallowRemainder(of event: NSEvent?) {
        guard let event,
              event.type == .keyDown,
              event.keyCode == EscapeKeyPressFilter.escapeKeyCode else { return }
        filter.arm()
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        scheduleReleaseCheck()
    }

    /// Returns `nil` for events that belong to the swallowed press.
    func handle(_ event: NSEvent) -> NSEvent? {
        let swallow = filter.shouldSwallow(
            isKeyDown: event.type == .keyDown,
            keyCode: event.keyCode,
            isRepeat: event.type == .keyDown && event.isARepeat
        )
        if !filter.isArmed {
            // Don't remove the monitor from inside its own callback.
            DispatchQueue.main.async { [weak self] in self?.stopIfDisarmed() }
        }
        return swallow ? nil : event
    }

    private func scheduleReleaseCheck() {
        releaseCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.filter.isArmed, self.isEscapeKeyDown() {
                self.scheduleReleaseCheck()
            } else {
                self.filter.disarm()
                self.stopIfDisarmed()
            }
        }
        releaseCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseCheckInterval, execute: work)
    }

    private func stopIfDisarmed() {
        guard !filter.isArmed else { return }
        releaseCheck?.cancel()
        releaseCheck = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
