import Testing
@testable import SharedKit

@Suite("Quick Access action layout")
struct QuickAccessActionLayoutTests {
    @Test("Core workflow remains one click without cloud sharing")
    func visibleActionsWithoutSharing() {
        #expect(QuickAccessActionLayout.visibleActions(sharingAvailable: false) == [
            .drag,
            .copy,
            .save,
            .annotate,
            .pin,
        ])
    }

    @Test("Cloud sharing adds Upload while intelligence actions stay in overflow")
    func visibleActionsWithSharing() {
        #expect(QuickAccessActionLayout.visibleActions(sharingAvailable: true) == [
            .drag,
            .copy,
            .save,
            .upload,
            .annotate,
            .pin,
        ])
        #expect(QuickAccessActionLayout.overflowActions == [.ocr, .translate])
    }
}
