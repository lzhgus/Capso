import XCTest
import KeyboardShortcuts
@testable import Capso

@MainActor
final class ShortcutConflictTests: XCTestCase {
    private var originalAllInOne: KeyboardShortcuts.Shortcut?
    private var originalCaptureArea: KeyboardShortcuts.Shortcut?
    private var originalRecordScreen: KeyboardShortcuts.Shortcut?

    override func setUp() {
        super.setUp()
        originalAllInOne = KeyboardShortcuts.Name.captureAllInOne.effectiveShortcut
        originalCaptureArea = KeyboardShortcuts.Name.captureArea.effectiveShortcut
        originalRecordScreen = KeyboardShortcuts.Name.recordScreen.effectiveShortcut
    }

    override func tearDown() {
        // Restore original state
        KeyboardShortcuts.setShortcut(originalAllInOne, for: .captureAllInOne)
        KeyboardShortcuts.setShortcut(originalCaptureArea, for: .captureArea)
        KeyboardShortcuts.setShortcut(originalRecordScreen, for: .recordScreen)
        super.tearDown()
    }

    func testEffectiveShortcutRespectsDefaultsAndDisabledState() {
        let name = KeyboardShortcuts.Name.captureArea
        let defaultShortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option, .shift])
        XCTAssertEqual(name.defaultShortcut, defaultShortcut)

        // 1. When cleared, UserDefaults has false, effectiveShortcut is nil
        KeyboardShortcuts.setShortcut(nil, for: name)
        UserDefaults.standard.set(false, forKey: "KeyboardShortcuts_" + name.rawValue)
        XCTAssertNil(name.effectiveShortcut)

        // 2. When reset, effectiveShortcut returns default
        KeyboardShortcuts.reset(name)
        XCTAssertEqual(name.effectiveShortcut, defaultShortcut)
    }

    func testResettingCommandRevertsConflictingOtherCommand() {
        let cmdA = KeyboardShortcuts.Name.captureArea
        let cmdB = KeyboardShortcuts.Name.captureAllInOne
        let defaultA = KeyboardShortcuts.Shortcut(.one, modifiers: [.option, .shift])

        // Step 1: User removes Command A's shortcut
        KeyboardShortcuts.setShortcut(nil, for: cmdA)
        UserDefaults.standard.set(false, forKey: "KeyboardShortcuts_" + cmdA.rawValue)
        XCTAssertNil(cmdA.effectiveShortcut)

        // Step 2: User sets Command B to ⌥⇧1
        KeyboardShortcuts.setShortcut(defaultA, for: cmdB)
        XCTAssertEqual(cmdB.effectiveShortcut, defaultA)

        // Step 3: User resets Command A to default via resetRevertingConflicts()
        cmdA.resetRevertingConflicts()

        // Verify: Command A is restored to ⌥⇧1
        XCTAssertEqual(cmdA.effectiveShortcut, defaultA)

        // Verify: Command B was reverted and NO LONGER has ⌥⇧1
        XCTAssertNotEqual(cmdB.effectiveShortcut, defaultA)
        XCTAssertNil(cmdB.effectiveShortcut)
    }

    func testResettingCommandRestoresOtherCommandWithItsOwnDefault() {
        let cmdA = KeyboardShortcuts.Name.captureArea       // default: ⌥⇧1
        let cmdB = KeyboardShortcuts.Name.captureFullscreen // default: ⌥⇧2
        let defaultA = KeyboardShortcuts.Shortcut(.one, modifiers: [.option, .shift])
        let defaultB = KeyboardShortcuts.Shortcut(.two, modifiers: [.option, .shift])

        // User removes cmdA
        KeyboardShortcuts.setShortcut(nil, for: cmdA)
        UserDefaults.standard.set(false, forKey: "KeyboardShortcuts_" + cmdA.rawValue)

        // User assigns cmdB to ⌥⇧1
        KeyboardShortcuts.setShortcut(defaultA, for: cmdB)
        XCTAssertEqual(cmdB.effectiveShortcut, defaultA)

        // User resets cmdA via resetRevertingConflicts()
        cmdA.resetRevertingConflicts()

        // Verify: cmdA has ⌥⇧1, and cmdB reverted to its own default ⌥⇧2
        XCTAssertEqual(cmdA.effectiveShortcut, defaultA)
        XCTAssertEqual(cmdB.effectiveShortcut, defaultB)
    }

    func testIsConflictingNormalizesKeypadAndTopRow() {
        let topRowOne = KeyboardShortcuts.Shortcut(.one, modifiers: [.option, .shift])
        let keypadOne = KeyboardShortcuts.Shortcut(carbonKeyCode: 83, carbonModifiers: topRowOne.carbonModifiers) // 83 is kVK_ANSI_Keypad1

        // Exact equality fails because keycodes differ (18 vs 83)
        XCTAssertNotEqual(topRowOne, keypadOne)

        // Conflict check succeeds because base keys normalize to the same key
        XCTAssertTrue(topRowOne.isConflicting(with: keypadOne))
        XCTAssertTrue(keypadOne.isConflicting(with: topRowOne))

        // Different modifiers do not conflict
        let keypadOneCommand = KeyboardShortcuts.Shortcut(.one, modifiers: [.command, .shift])
        XCTAssertFalse(topRowOne.isConflicting(with: keypadOneCommand))
    }

    func testResettingCommandRevertsKeypadConflictingOtherCommand() {
        let cmdA = KeyboardShortcuts.Name.captureArea // default: ⌥⇧1 (keycode 18)
        let cmdB = KeyboardShortcuts.Name.captureAllInOne
        let defaultA = KeyboardShortcuts.Shortcut(.one, modifiers: [.option, .shift])
        let keypadShortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: 83, carbonModifiers: defaultA.carbonModifiers)

        // User removes cmdA
        KeyboardShortcuts.setShortcut(nil, for: cmdA)
        UserDefaults.standard.set(false, forKey: "KeyboardShortcuts_" + cmdA.rawValue)

        // User assigns cmdB using keypad 1
        KeyboardShortcuts.setShortcut(keypadShortcut, for: cmdB)
        XCTAssertEqual(cmdB.effectiveShortcut, keypadShortcut)

        // User resets cmdA
        cmdA.resetRevertingConflicts()

        // cmdA restored to default
        XCTAssertEqual(cmdA.effectiveShortcut, defaultA)

        // cmdB should have been detected as conflicting despite keypad keycode and reverted (cleared)
        XCTAssertNil(cmdB.effectiveShortcut)
    }
}
