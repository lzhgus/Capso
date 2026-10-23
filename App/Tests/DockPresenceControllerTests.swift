import AppKit
import XCTest
@testable import Capso

@MainActor
final class DockPresenceControllerTests: XCTestCase {
    private func makeWindow(tagged: Bool = true) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        if tagged {
            window.identifier = DockPresenceController.windowIdentifier
        }
        return window
    }

    func testVisibleTaggedWindowShowsInDock() {
        let window = makeWindow()
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        XCTAssertTrue(DockPresenceController.shouldShowInDock(windows: [window]))
    }

    func testOrderedOutTaggedWindowDoesNotCount() {
        let window = makeWindow()
        window.orderFront(nil)
        window.orderOut(nil)
        XCTAssertFalse(DockPresenceController.shouldShowInDock(windows: [window]))
    }

    func testHidingTheAppKeepsTheDockTile() {
        let window = makeWindow()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(
            DockPresenceController.policy(windows: [window], appIsHidden: true, current: .regular),
            .regular
        )
        XCTAssertEqual(
            DockPresenceController.policy(windows: [window], appIsHidden: false, current: .regular),
            .accessory
        )
    }

    func testUntaggedTitledWindowsDoNotCount() {
        let window = makeWindow(tagged: false)
        window.orderFront(nil)
        let colorPanel = NSColorPanel.shared
        colorPanel.orderFront(nil)
        defer {
            window.orderOut(nil)
            colorPanel.orderOut(nil)
        }
        XCTAssertFalse(DockPresenceController.shouldShowInDock(windows: [window, colorPanel]))
    }
}

@MainActor
final class DockPresenceControllerIntegrationTests: XCTestCase {
    private func drainMainQueue() {
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    func testPolicyFollowsEditorLifecycle() {
        let originalPolicy = NSApp.activationPolicy()
        defer {
            NSApp.setActivationPolicy(originalPolicy)
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.setActivationPolicy(.accessory)
        let controller = DockPresenceController()
        _ = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.identifier = DockPresenceController.windowIdentifier

        window.makeKeyAndOrderFront(nil)
        drainMainQueue()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)

        window.close()
        drainMainQueue()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }
}
