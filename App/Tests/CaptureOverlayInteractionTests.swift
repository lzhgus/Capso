import AppKit
import XCTest
@testable import Capso
import SharedKit

@MainActor
final class CaptureOverlayInteractionTests: XCTestCase {
    func testEscapeEventClearsMultiSelectionWithoutCancellingOtherDisplayOverlay() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true
        )
        let secondWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: false
        )
        let firstView = try XCTUnwrap(firstWindow.contentView as? CaptureOverlayView)
        let secondView = try XCTUnwrap(secondWindow.contentView as? CaptureOverlayView)

        firstView.setMode(.windowSelection([]))
        secondView.setMode(.windowSelection([]))
        NotificationCenter.default.post(
            name: .multiWindowSelectionChanged,
            object: self,
            userInfo: ["windowIDs": [NSNumber(value: CGWindowID(42))]]
        )

        var cancellationCount = 0
        firstWindow.onCancelled = { cancellationCount += 1 }
        secondWindow.onCancelled = { cancellationCount += 1 }

        let firstEscape = try makeEscapeEvent(windowNumber: firstWindow.windowNumber)
        XCTAssertNil(firstWindow.handleLocalKeyEvent(firstEscape))
        XCTAssertTrue(secondWindow.handleLocalKeyEvent(firstEscape) === firstEscape)
        XCTAssertEqual(cancellationCount, 0)

        let secondEscape = try makeEscapeEvent(windowNumber: secondWindow.windowNumber)
        XCTAssertNil(secondWindow.handleLocalKeyEvent(secondEscape))
        XCTAssertEqual(cancellationCount, 1)
    }

    func testGlobalEscapeUsesOneOwnerWhenNoOverlayIsKey() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true
        )
        let secondWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: false
        )
        let firstView = try XCTUnwrap(firstWindow.contentView as? CaptureOverlayView)
        let secondView = try XCTUnwrap(secondWindow.contentView as? CaptureOverlayView)

        firstView.setMode(.windowSelection([]))
        secondView.setMode(.windowSelection([]))
        NotificationCenter.default.post(
            name: .multiWindowSelectionChanged,
            object: self,
            userInfo: ["windowIDs": [NSNumber(value: CGWindowID(42))]]
        )

        var cancellationCount = 0
        firstWindow.onCancelled = { cancellationCount += 1 }
        secondWindow.onCancelled = { cancellationCount += 1 }

        XCTAssertFalse(firstWindow.isKeyWindow)
        XCTAssertFalse(secondWindow.isKeyWindow)

        let escape = try makeEscapeEvent(windowNumber: 0)
        firstWindow.handleGlobalKeyEvent(escape)
        secondWindow.handleGlobalKeyEvent(escape)
        XCTAssertEqual(cancellationCount, 0)

        firstWindow.handleGlobalKeyEvent(escape)
        secondWindow.handleGlobalKeyEvent(escape)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testGlobalShiftReleaseConfirmsSelectionWhenNoOverlayIsKey() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let firstWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: true
        )
        let secondWindow = CaptureOverlayWindow(
            screen: screen,
            settings: settings,
            handlesGlobalKeyEvents: false
        )
        let firstView = try XCTUnwrap(firstWindow.contentView as? CaptureOverlayView)
        let secondView = try XCTUnwrap(secondWindow.contentView as? CaptureOverlayView)

        firstView.setMode(.windowSelection([]))
        secondView.setMode(.windowSelection([]))
        NotificationCenter.default.post(
            name: .multiWindowSelectionChanged,
            object: self,
            userInfo: [
                "windowIDs": [
                    NSNumber(value: CGWindowID(42)),
                    NSNumber(value: CGWindowID(43))
                ]
            ]
        )

        var capturedSelections: [[CGWindowID]] = []
        firstWindow.onWindowsSelected = { capturedSelections.append($0) }
        secondWindow.onWindowsSelected = { capturedSelections.append($0) }

        XCTAssertFalse(firstWindow.isKeyWindow)
        XCTAssertFalse(secondWindow.isKeyWindow)

        let commandChanged = try makeFlagsChangedEvent(modifierFlags: .command, keyCode: 55)
        firstWindow.handleGlobalFlagsChanged(commandChanged)
        secondWindow.handleGlobalFlagsChanged(commandChanged)
        XCTAssertTrue(capturedSelections.isEmpty)

        let shiftReleased = try makeFlagsChangedEvent(modifierFlags: [])
        firstWindow.handleGlobalFlagsChanged(shiftReleased)
        secondWindow.handleGlobalFlagsChanged(shiftReleased)

        XCTAssertEqual(capturedSelections, [[42, 43]])
    }

    func testRecordingWindowSelectionTreatsShiftClickAsSingleSelection() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let screen = try XCTUnwrap(NSScreen.main)
        let hostWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            settings: settings,
            safeAreaTopInset: 0,
            presetsDisabled: true,
            allowsMultiWindowSelection: false
        )
        hostWindow.contentView = view
        view.setMode(.windowSelection([]))

        var selectedWindowID: CGWindowID?
        view.onWindowSelected = { selectedWindowID = $0 }
        view.handleWindowClick(42, modifierFlags: .shift)

        XCTAssertEqual(selectedWindowID, 42)
        XCTAssertFalse(view.handleEscapeKey(), "Shift-click must not leave recording in multi-select state")
    }

    func testSingleShiftSelectionUsesSingleWindowCallback() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let view = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
            settings: settings,
            safeAreaTopInset: 0
        )
        view.setMode(.windowSelection([]))

        var selectedWindowID: CGWindowID?
        var selectedWindowIDs: [CGWindowID]?
        view.onWindowSelected = { selectedWindowID = $0 }
        view.onWindowsSelected = { selectedWindowIDs = $0 }

        view.handleWindowClick(42, modifierFlags: .shift)
        view.handleFlagsChanged(try makeFlagsChangedEvent(modifierFlags: []))

        XCTAssertEqual(selectedWindowID, 42)
        XCTAssertNil(selectedWindowIDs)
    }

    // MARK: - Shift square lock

    func testShiftPressedBeforeFirstDragKeepsSelectionAnchoredAtPressPoint() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let view = makeAreaOverlayView(settings: settings)
        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 180, y: 140)))
        view.flagsChanged(with: try makeFlagsChangedEvent(modifierFlags: .shift))

        // Nothing has moved yet, so the square lock must resolve to an empty
        // selection at the press point — not jump toward the screen origin.
        XCTAssertEqual(view.selectionRect, CGRect(x: 180, y: 140, width: 0, height: 0))
    }

    func testShiftDuringDragSquaresSelectionFromLastPointerLocation() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let view = makeAreaOverlayView(settings: settings)
        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 180, y: 140)))
        view.mouseDragged(with: try makeMouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 200)))
        XCTAssertEqual(view.selectionRect, CGRect(x: 180, y: 140, width: 120, height: 60))

        view.flagsChanged(with: try makeFlagsChangedEvent(modifierFlags: .shift))
        XCTAssertEqual(view.selectionRect, CGRect(x: 180, y: 140, width: 120, height: 120))

        view.flagsChanged(with: try makeFlagsChangedEvent(modifierFlags: []))
        XCTAssertEqual(view.selectionRect, CGRect(x: 180, y: 140, width: 120, height: 60))
    }

    func testSecondDragDoesNotReusePreviousDragEndpoint() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let view = makeAreaOverlayView(settings: settings)
        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 180, y: 140)))
        view.mouseDragged(with: try makeMouseEvent(.leftMouseDragged, at: NSPoint(x: 400, y: 300)))
        view.mouseUp(with: try makeMouseEvent(.leftMouseUp, at: NSPoint(x: 400, y: 300)))

        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 100, y: 100)))
        view.flagsChanged(with: try makeFlagsChangedEvent(modifierFlags: .shift))

        XCTAssertEqual(view.selectionRect, CGRect(x: 100, y: 100, width: 0, height: 0))
    }

    func testFlagsMonitorPathAppliesSquareLockWhenViewIsNotFirstResponder() throws {
        let (settings, defaultsSuiteName) = makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        let view = makeAreaOverlayView(settings: settings, allowsMultiWindowSelection: false)
        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 180, y: 140)))
        view.mouseDragged(with: try makeMouseEvent(.leftMouseDragged, at: NSPoint(x: 300, y: 200)))

        // The window's local flags monitor calls handleFlagsChanged directly,
        // bypassing the view's flagsChanged responder path.
        view.handleFlagsChanged(try makeFlagsChangedEvent(modifierFlags: .shift))

        XCTAssertEqual(view.selectionRect, CGRect(x: 180, y: 140, width: 120, height: 120))
    }

    func testAllInOneShiftBeforeFirstDragCreatesSquareAtPressPoint() throws {
        let (view, previews) = makeAllInOneOverlayView(activePreset: .freeform)

        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 120, y: 100)))
        view.handleFlagsChanged(try makeFlagsChangedEvent(modifierFlags: .shift))

        // No movement yet, so the square collapses to the minimum size anchored
        // at the press point instead of being derived from `.zero`.
        XCTAssertEqual(try XCTUnwrap(previews.last), CGRect(x: 120, y: 100, width: 24, height: 24))
    }

    func testAllInOneShiftBeforeFirstDragKeepsFixedSizeSelectionCentered() throws {
        let (view, previews) = makeAllInOneOverlayView(
            activePreset: .fixedSize(width: 200, height: 100, name: nil)
        )

        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 700, y: 500)))
        let centered = try XCTUnwrap(previews.last)
        XCTAssertEqual(centered, CGRect(x: 600, y: 450, width: 200, height: 100))

        // Shift before the first drag must not move the fixed-size selection.
        view.handleFlagsChanged(try makeFlagsChangedEvent(modifierFlags: .shift))
        XCTAssertEqual(previews.last, centered)
    }

    func testAllInOneSecondDragDoesNotReusePreviousDragEndpoint() throws {
        let (view, previews) = makeAllInOneOverlayView(activePreset: .freeform)

        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 120, y: 100)))
        view.mouseDragged(with: try makeMouseEvent(.leftMouseDragged, at: NSPoint(x: 400, y: 300)))
        view.mouseUp(with: try makeMouseEvent(.leftMouseUp, at: NSPoint(x: 400, y: 300)))

        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: NSPoint(x: 200, y: 450)))
        view.handleFlagsChanged(try makeFlagsChangedEvent(modifierFlags: .shift))

        // A minimum square at the new press point — the previous drag's endpoint
        // (400, 300) must not size this one.
        XCTAssertEqual(try XCTUnwrap(previews.last), CGRect(x: 200, y: 426, width: 24, height: 24))
    }

    private func makeAreaOverlayView(
        settings: AppSettings,
        allowsMultiWindowSelection: Bool = true
    ) -> CaptureOverlayView {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let view = CaptureOverlayView(
            frame: frame,
            settings: settings,
            safeAreaTopInset: 0,
            allowsMultiWindowSelection: allowsMultiWindowSelection
        )
        let hostWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = view
        view.setMode(.area)
        return view
    }

    /// Hosts the all-in-one selection overlay and records every live preview it
    /// publishes, which is how the window observes selection changes.
    private func makeAllInOneOverlayView(
        activePreset: CapturePreset
    ) -> (AllInOneSelectionOverlayView, PreviewRecorder) {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let view = AllInOneSelectionOverlayView(
            frame: frame,
            selectionRect: CGRect(x: 200, y: 160, width: 300, height: 200),
            minSelectionSize: CGSize(width: 24, height: 24),
            activePreset: activePreset
        )
        let hostWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = view

        let recorder = PreviewRecorder()
        view.onSelectionPreviewChanged = { recorder.rects.append($0) }
        return (view, recorder)
    }

    @MainActor
    private final class PreviewRecorder {
        var rects: [CGRect] = []
        var last: CGRect? { rects.last }
    }

    private func makeMouseEvent(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func makeSettings() -> (AppSettings, String) {
        let suiteName = "CaptureOverlayInteractionTests.\(UUID().uuidString)"
        return (AppSettings(defaults: UserDefaults(suiteName: suiteName)!), suiteName)
    }

    private func makeEscapeEvent(windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    private func makeFlagsChangedEvent(
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16 = 56
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
