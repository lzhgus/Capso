import Testing
import CoreImage
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
        let provider = CursorOverlayProvider(events: [])
        #expect(provider.clickScale(at: 3.0) == 1.0)
    }

    @Test("Far from any click returns scale 1.0")
    func farFromClick() {
        let provider = CursorOverlayProvider(events: makeClicks())
        #expect(provider.clickScale(at: 0.0) == 1.0)
        #expect(provider.clickScale(at: 10.0) == 1.0)
    }

    @Test("At exact click time returns minimum scale")
    func atClickTime() {
        let provider = CursorOverlayProvider(events: makeClicks())
        let scale = provider.clickScale(at: 2.0)
        #expect(scale < 1.0)
        #expect(scale >= 0.8)
    }

    @Test("Before click window returns 1.0")
    func beforeClick() {
        let provider = CursorOverlayProvider(events: makeClicks())
        #expect(provider.clickScale(at: 1.87) == 1.0)
    }

    @Test("During click shrink returns scale between 0.8 and 1.0")
    func duringClick() {
        let provider = CursorOverlayProvider(events: makeClicks())
        let scale = provider.clickScale(at: 2.05)
        #expect(scale >= 0.8)
        #expect(scale <= 1.0)
    }

    @Test("After click recovery returns scale 1.0")
    func afterClickRecovery() {
        let provider = CursorOverlayProvider(events: makeClicks())
        #expect(provider.clickScale(at: 2.2) == 1.0)
    }

    // MARK: - Idle hiding

    /// Moves every 50 ms during each range, nothing in between.
    private func moves(during ranges: [ClosedRange<Double>]) -> [CursorEvent] {
        ranges.flatMap { range in
            stride(from: range.lowerBound, through: range.upperBound, by: 0.05).map {
                CursorEvent(timestamp: $0, x: 0.5, y: 0.5, type: .move)
            }
        }
    }

    @Test("A pause of 1.5 s or more fades the cursor out and back in around it")
    func longPauseHides() {
        let provider = CursorOverlayProvider(events: moves(during: [0...2, 5...6]), hidesIdleCursor: true)
        #expect(provider.opacity(at: 1.0) == 1)
        #expect(provider.opacity(at: 2.05) == 1)
        let midFade = provider.opacity(at: 2.0 + 0.1 + 0.15)
        #expect(midFade > 0.4 && midFade < 0.6)
        #expect(provider.opacity(at: 3.5) == 0)
        #expect(provider.opacity(at: 4.85) > 0 && provider.opacity(at: 4.85) < 1)
        #expect(provider.opacity(at: 5.0) == 1)
    }

    @Test("Short pauses never hide the cursor")
    func shortPauseStaysVisible() {
        let provider = CursorOverlayProvider(events: moves(during: [0...2, 3.4...5]), hidesIdleCursor: true)
        for step in 0...100 {
            #expect(provider.opacity(at: Double(step) * 0.05) == 1)
        }
    }

    @Test("Typing while the mouse is still hides the cursor")
    func typingHides() {
        let keys = stride(from: 2.2, through: 4.5, by: 0.2).map { CursorEvent(timestamp: $0, x: 0.5, y: 0.5, type: .keyDown) }
        let provider = CursorOverlayProvider(events: moves(during: [0...2, 5...6]) + keys, hidesIdleCursor: true)
        #expect(provider.opacity(at: 3.5) == 0)
    }

    @Test("The cursor stays hidden after the last movement, and is always shown when the option is off")
    func endAndDisabled() {
        let events = moves(during: [0...2, 5...6])
        #expect(CursorOverlayProvider(events: events, hidesIdleCursor: true).opacity(at: 9) == 0)
        let off = CursorOverlayProvider(events: events, hidesIdleCursor: false)
        #expect(off.opacity(at: 3.5) == 1 && off.opacity(at: 9) == 1)
    }

    @Test("A hidden cursor is not drawn; a half-faded one is drawn at half alpha")
    func styledCursorAlpha() {
        let provider = CursorOverlayProvider(events: moves(during: [0...2, 5...6]), hidesIdleCursor: true)
        let white = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        #expect(provider.styledCursor(white, at: 3.5) == nil)
        let half = provider.styledCursor(white, at: 2.25)!
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(half, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
        #expect(pixel[3] > 100 && pixel[3] < 155)
    }

    @Test("Stillness at the start of a recording, or typing only, also hides the cursor")
    func stillFromTheStart() {
        let lateStart = CursorOverlayProvider(events: moves(during: [4...6]), hidesIdleCursor: true)
        #expect(lateStart.opacity(at: 0) == 1)
        #expect(lateStart.opacity(at: 2) == 0)
        #expect(lateStart.opacity(at: 4) == 1)

        let keys = stride(from: 0.5, through: 5, by: 0.2).map { CursorEvent(timestamp: $0, x: 0.5, y: 0.5, type: .keyDown) }
        let typingOnly = CursorOverlayProvider(events: keys, hidesIdleCursor: true)
        #expect(typingOnly.opacity(at: 3) == 0)
    }
}
