import AppKit
import SharedKit
import SwiftUI
import XCTest
@testable import Capso

@MainActor
final class QuickAccessSettingsLayoutTests: XCTestCase {
    func testPositionPickerStaysInsideSettingsContent() throws {
        let suiteName = "QuickAccessSettingsLayoutTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let viewModel = PreferencesViewModel(
            settings: settings,
            permissionManager: PermissionManager()
        )
        let hostingView = NSHostingView(rootView: QuickAccessSettingsView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 443, height: 260)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let positionPicker = try XCTUnwrap(
            firstSubview(of: NSSegmentedControl.self, in: hostingView) { $0.segmentCount == 3 }
        )
        let pickerFrame = hostingView.convert(positionPicker.bounds, from: positionPicker)

        XCTAssertGreaterThanOrEqual(pickerFrame.minX, hostingView.bounds.minX)
        XCTAssertLessThanOrEqual(
            pickerFrame.maxX,
            hostingView.bounds.maxX - 14,
            "Position picker violates the settings card inset: \(pickerFrame) in \(hostingView.bounds)"
        )
    }

    private func firstSubview<T: NSView>(
        of type: T.Type,
        in root: NSView,
        where predicate: (T) -> Bool
    ) -> T? {
        if let match = root as? T, predicate(match) {
            return match
        }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview, where: predicate) {
                return match
            }
        }
        return nil
    }
}
