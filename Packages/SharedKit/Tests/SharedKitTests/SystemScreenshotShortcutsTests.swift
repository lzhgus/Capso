import Testing
@testable import SharedKit

@Suite("System screenshot shortcuts")
struct SystemScreenshotShortcutsTests {
    private func hotKeys(_ enabled: [String: Bool]) -> [String: Any] {
        enabled.mapValues { ["enabled": $0, "value": ["parameters": [51, 20, 1179648], "type": "standard"]] as [String: Any] }
    }

    @Test("All three turned off")
    func allOff() {
        #expect(!SystemScreenshotShortcuts.areEnabled(in: hotKeys(["28": false, "30": false, "184": false])))
    }

    @Test("Any one still on counts as on", arguments: ["28", "30", "184"])
    func oneOn(id: String) {
        var states = ["28": false, "30": false, "184": false]
        states[id] = true
        #expect(SystemScreenshotShortcuts.areEnabled(in: hotKeys(states)))
    }

    @Test("Never changed (no entries) means macOS still uses them")
    func missingMeansOn() {
        #expect(SystemScreenshotShortcuts.areEnabled(in: nil))
        #expect(SystemScreenshotShortcuts.areEnabled(in: hotKeys(["28": false, "30": false])))
    }

    @Test("The clipboard variants don't matter")
    func clipboardVariantsIgnored() {
        #expect(!SystemScreenshotShortcuts.areEnabled(in: hotKeys(["28": false, "29": true, "30": false, "31": true, "184": false])))
    }
}
