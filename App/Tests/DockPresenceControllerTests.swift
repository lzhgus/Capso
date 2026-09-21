import AppKit
import XCTest
@testable import Capso

@MainActor
final class DockPresenceControllerTests: XCTestCase {
    private func makeWindow(styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    func testNoWindowsHidesFromDock() {
        XCTAssertFalse(DockPresenceController.shouldShowInDock(windows: []))
    }

    func testVisibleTitledClosableWindowShowsInDock() {
        let window = makeWindow(styleMask: [.titled, .closable, .resizable])
        window.orderFront(nil)
        XCTAssertTrue(DockPresenceController.shouldShowInDock(windows: [window]))
        window.orderOut(nil)
    }

    func testHiddenTitledWindowDoesNotCount() {
        let window = makeWindow(styleMask: [.titled, .closable])
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(DockPresenceController.shouldShowInDock(windows: [window]))
    }

    func testBorderlessOverlayDoesNotCount() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(DockPresenceController.shouldShowInDock(windows: [panel]))
        panel.orderOut(nil)
    }

    func testOrderedOutWindowNoLongerCounts() {
        let window = makeWindow(styleMask: [.titled, .closable])
        window.orderFront(nil)
        XCTAssertTrue(DockPresenceController.shouldShowInDock(windows: [window]))
        window.orderOut(nil)
        XCTAssertFalse(DockPresenceController.shouldShowInDock(windows: [window]))
    }
}

@MainActor
final class DockPresenceControllerIntegrationTests: XCTestCase {
    /// Spin the main run loop so the coalesced policy update gets a chance to run.
    private func drainMainQueue() {
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    func testPolicyFollowsDocumentWindowLifecycle() {
        let originalPolicy = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(originalPolicy) }

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

        window.makeKeyAndOrderFront(nil)
        drainMainQueue()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)

        window.close()
        drainMainQueue()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }
}
