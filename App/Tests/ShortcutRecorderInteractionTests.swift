import AppKit
@preconcurrency import KeyboardShortcuts
import XCTest
@testable import Capso

@MainActor
final class ShortcutRecorderInteractionTests: XCTestCase {
    func testCatalogIncludesEveryGlobalShortcutExactlyOnce() {
        let names = ShortcutCatalog.entries.map(\.name)
        XCTAssertEqual(Set(names), Set(KeyboardShortcuts.Name.allCapso))
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testSingleClickRecordsFirstCombinationAndRestoresGlobalShortcuts() throws {
        try withControl { window, control in
            let initiallyEnabled = KeyboardShortcuts.isEnabled
            control.recordButton.performClick(nil)
            XCTAssertTrue(control.isRecording)
            XCTAssertFalse(KeyboardShortcuts.isEnabled)
            XCTAssertEqual(control.recordButton.title, String(localized: "Press a shortcut…"))
            XCTAssertTrue(control.recordButton.acceptsFirstMouse(for: nil))
            NSApp.sendEvent(try keyEvent(keyCode: 40, characters: "k", modifiers: [.control, .option], window: window))
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: control.name), .init(.k, modifiers: [.control, .option]))
            XCTAssertFalse(control.isRecording)
            XCTAssertEqual(KeyboardShortcuts.isEnabled, initiallyEnabled)
        }
    }

    func testEscapePreservesExistingShortcutAndDeleteRemovesIt() throws {
        try withControl { window, control in
            let original = KeyboardShortcuts.Shortcut(.k, modifiers: [.control, .option])
            KeyboardShortcuts.setShortcut(original, for: control.name)
            control.recordButton.performClick(nil)
            NSApp.sendEvent(try keyEvent(keyCode: 53, characters: "\u{1B}", window: window))
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: control.name), original)
            XCTAssertFalse(control.isRecording)
            control.recordButton.performClick(nil)
            NSApp.sendEvent(try keyEvent(keyCode: 51, characters: "\u{7F}", window: window))
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: control.name))
            XCTAssertFalse(control.isRecording)
        }
    }

    func testModifierFeedbackAndInvalidKeyKeepSessionActive() throws {
        try withControl { window, control in
            control.recordButton.performClick(nil)
            let flags = try keyEvent(type: .flagsChanged, keyCode: 55, characters: "", modifiers: [.command], window: window)
            _ = control.handle(flags)
            XCTAssertTrue(control.recordButton.title.contains("⌘"))
            XCTAssertNil(control.handle(try keyEvent(keyCode: 40, characters: "k", window: window)))
            XCTAssertTrue(control.isRecording)
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: control.name))
            XCTAssertEqual(control.recordButton.title, String(localized: "Add ⌘, ⌃ or ⌥"))
        }
    }

    func testFocusLossCancelsAndNextClickRestarts() throws {
        try withControl { window, control in
            control.recordButton.performClick(nil)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            XCTAssertFalse(control.isRecording)
            control.recordButton.performClick(nil)
            XCTAssertTrue(control.isRecording)
            NSApp.sendEvent(try keyEvent(keyCode: 40, characters: "k", modifiers: [.control, .option], window: window))
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: control.name), .init(.k, modifiers: [.control, .option]))
        }
    }

    func testClearButtonAndOutsideClick() throws {
        try withControl { window, control in
            KeyboardShortcuts.setShortcut(.init(.k, modifiers: [.control, .option]), for: control.name)
            control.refreshTitle()
            XCTAssertTrue(control.clearButton.isEnabled)
            control.clearButton.performClick(nil)
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: control.name))
            XCTAssertFalse(control.clearButton.isEnabled)
            control.recordButton.performClick(nil)
            let click = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 250, y: 50), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ))
            XCTAssertTrue(control.handle(click) === click)
            XCTAssertFalse(control.isRecording)
        }
    }

    func testRecordingPreservesPreviouslyDisabledGlobalShortcuts() throws {
        let previous = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        defer { KeyboardShortcuts.isEnabled = previous }
        try withControl { _, control in
            control.beginRecording()
            control.finishRecording()
            XCTAssertFalse(KeyboardShortcuts.isEnabled)
        }
    }

    func testMainMenuConflictRecognizesShiftedKeyInSubmenu() throws {
        let menu = NSMenu()
        let parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let save = NSMenuItem(title: "Save As", action: nil, keyEquivalent: "S")
        save.keyEquivalentModifierMask = .command
        submenu.addItem(save)
        parent.submenu = submenu
        menu.addItem(parent)
        try withControl { window, _ in
            let event = try keyEvent(keyCode: 1, characters: "S", modifiers: [.command, .shift], window: window)
            XCTAssertEqual(ShortcutRecorderContainer.conflictingMenuItem(for: event, in: menu), "Save As")
        }
    }

    func testSwitchingRecordersKeepsGlobalsDisabledUntilLastSessionEnds() throws {
        try withControl { window, first in
            let secondName = KeyboardShortcuts.Name("recorder-test-\(UUID().uuidString)")
            let second = ShortcutRecorderContainer(name: secondName)
            defer {
                second.finishRecording()
                KeyboardShortcuts.setShortcut(nil, for: secondName)
            }
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 170, height: 80))
            window.contentView = root
            root.addSubview(first)
            root.addSubview(second)
            let previous = KeyboardShortcuts.isEnabled
            first.beginRecording()
            second.beginRecording()
            XCTAssertFalse(first.isRecording)
            XCTAssertTrue(second.isRecording)
            XCTAssertFalse(KeyboardShortcuts.isEnabled)
            second.finishRecording()
            XCTAssertEqual(KeyboardShortcuts.isEnabled, previous)
        }
    }

    func testClosingSettingsEndsRecordingAndRestoresGlobalShortcuts() throws {
        try withControl { window, control in
            let previous = KeyboardShortcuts.isEnabled
            control.beginRecording()
            window.close()
            XCTAssertFalse(control.isRecording)
            XCTAssertEqual(KeyboardShortcuts.isEnabled, previous)
        }
    }

    func testDuplicateBindingShowsNamedAlertAndPreservesBothShortcuts() throws {
        let occupied = KeyboardShortcuts.Name("recorder-test-occupied-\(UUID().uuidString)")
        let duplicate = KeyboardShortcuts.Shortcut(.k, modifiers: [.control, .option])
        KeyboardShortcuts.setShortcut(duplicate, for: occupied)
        defer { KeyboardShortcuts.setShortcut(nil, for: occupied) }
        try withControl(shortcuts: [.init(name: occupied, title: "全能截图")]) { window, control in
            let original = KeyboardShortcuts.Shortcut(.j, modifiers: [.control, .option])
            KeyboardShortcuts.setShortcut(original, for: control.name)
            let initiallyEnabled = KeyboardShortcuts.isEnabled
            control.beginRecording()
            XCTAssertNil(control.handle(try keyEvent(keyCode: 40, characters: "k", modifiers: [.control, .option], window: window)))
            let alert = try XCTUnwrap(control.conflictAlert)
            XCTAssertTrue(window.attachedSheet === alert.window)
            XCTAssertTrue(alert.informativeText.contains("全能截图"))
            XCTAssertTrue(alert.informativeText.contains(duplicate.description))
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: control.name), original)
            XCTAssertEqual(KeyboardShortcuts.getShortcut(for: occupied), duplicate)
            XCTAssertFalse(control.isRecording)
            XCTAssertEqual(KeyboardShortcuts.isEnabled, initiallyEnabled)
            // Releasing modifiers must not erase the conflict message.
            _ = control.handle(try keyEvent(type: .flagsChanged, keyCode: 58, characters: "", window: window))
            XCTAssertTrue(window.attachedSheet === alert.window)
        }
    }

    func testDuplicateLookupExcludesSelfAndDistinguishesModifiers() throws {
        let name = KeyboardShortcuts.Name("recorder-test-self-\(UUID().uuidString)")
        let other = KeyboardShortcuts.Name("recorder-test-other-\(UUID().uuidString)")
        let original = KeyboardShortcuts.Shortcut(.k, modifiers: [.control, .option])
        KeyboardShortcuts.setShortcut(original, for: name)
        KeyboardShortcuts.setShortcut(.init(.k, modifiers: [.control, .shift]), for: other)
        defer {
            KeyboardShortcuts.setShortcut(nil, for: name)
            KeyboardShortcuts.setShortcut(nil, for: other)
        }
        let control = ShortcutRecorderContainer(name: name, shortcuts: [
            .init(name: name, title: "Current action"), .init(name: other, title: "Other action")
        ])
        XCTAssertNil(control.conflictingAction(for: original))
        XCTAssertEqual(control.conflictingAction(for: .init(.k, modifiers: [.control, .shift])), "Other action")
        KeyboardShortcuts.setShortcut(nil, for: other)
        XCTAssertNil(control.conflictingAction(for: .init(.k, modifiers: [.control, .shift])))
    }

    func testMenuConflictShowsPersistentAlertAndDoesNotSave() throws {
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Test menu action", action: nil, keyEquivalent: "k")
        item.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(item)
        NSApp.mainMenu = menu
        try withControl { window, control in
            control.beginRecording()
            _ = control.handle(try keyEvent(keyCode: 40, characters: "k", modifiers: [.control, .option], window: window))
            XCTAssertTrue(try XCTUnwrap(control.conflictAlert).informativeText.contains("Test menu action"))
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: control.name))
            XCTAssertFalse(control.isRecording)
        }
    }

    private func withControl(shortcuts: [ShortcutCatalog.Entry] = [], _ body: (NSWindow, ShortcutRecorderContainer) throws -> Void) throws {
        let name = KeyboardShortcuts.Name("recorder-test-\(UUID().uuidString)")
        let control = ShortcutRecorderContainer(name: name, shortcuts: shortcuts)
        let window = NSWindow(contentRect: control.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = control
        window.makeKeyAndOrderFront(nil)
        defer {
            control.finishRecording()
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
        try body(window, control)
    }

    private func keyEvent(
        type: NSEvent.EventType = .keyDown, keyCode: UInt16, characters: String,
        modifiers: NSEvent.ModifierFlags = [], window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }
}
