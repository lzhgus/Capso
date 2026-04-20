import Testing
import Foundation
@testable import EditorKit
import EffectsKit

@Suite("CursorOverlayProvider")
struct CursorOverlayProviderTests {

    private func makeClicks() -> [CursorEvent] {
        [
            CursorEvent(timestamp: 2.0, x: 0.5, y: 0.5, type: .leftClick),
            CursorEvent(timestamp: 5.0, x: 0.3, y: 0.7, type: .rightClick),
        ]
    }

    @Test("No clicks returns scale 1.0")
    func noClicks() {
        let provider = CursorOverlayProvider(clickEvents: [])
        #expect(provider.clickScale(at: 3.0) == 1.0)
    }

    @Test("Far from any click returns scale 1.0")
    func farFromClick() {
        let provider = CursorOverlayProvider(clickEvents: makeClicks())
        #expect(provider.clickScale(at: 0.0) == 1.0)
        #expect(provider.clickScale(at: 10.0) == 1.0)
    }

    @Test("At exact click time returns minimum scale")
    func atClickTime() {
        let provider = CursorOverlayProvider(clickEvents: makeClicks())
        let scale = provider.clickScale(at: 2.0)
        #expect(scale < 1.0)
        #expect(scale >= 0.8)
    }

    @Test("Before click window returns 1.0")
    func beforeClick() {
        let provider = CursorOverlayProvider(clickEvents: makeClicks())
        #expect(provider.clickScale(at: 1.87) == 1.0)
    }

    @Test("During click shrink returns scale between 0.8 and 1.0")
    func duringClick() {
        let provider = CursorOverlayProvider(clickEvents: makeClicks())
        let scale = provider.clickScale(at: 2.05)
        #expect(scale >= 0.8)
        #expect(scale <= 1.0)
    }

    @Test("After click recovery returns scale 1.0")
    func afterClickRecovery() {
        let provider = CursorOverlayProvider(clickEvents: makeClicks())
        #expect(provider.clickScale(at: 2.2) == 1.0)
    }
}
