import CoreGraphics
import Testing
@testable import SharedKit

@Suite("KeyPressOverlayPlacement")
struct KeyPressOverlayPlacementTests {
    private let recording = CGRect(x: 100, y: 200, width: 800, height: 600)
    private let size = CGSize(width: 120, height: 48)
    private let margin: CGFloat = 24

    @Test("Default origin is bottom-leading inside the recording frame")
    func defaultOriginBottomLeading() {
        let origin = KeyPressOverlayPlacement.defaultOrigin(
            recordingFrame: recording,
            size: size,
            margin: margin
        )
        #expect(origin.x == recording.minX + margin)
        #expect(origin.y == recording.minY + margin)
    }

    @Test("Saved offset restores relative to the current recording frame")
    func savedOffsetIsRelative() {
        let origin = KeyPressOverlayPlacement.origin(
            savedOffsetX: 40,
            savedOffsetY: 60,
            recordingFrame: recording,
            size: size,
            margin: margin
        )
        #expect(origin.x == recording.minX + 40)
        #expect(origin.y == recording.minY + 60)
    }

    @Test("Missing offset falls back to default corner")
    func missingOffsetUsesDefault() {
        let origin = KeyPressOverlayPlacement.origin(
            savedOffsetX: nil,
            savedOffsetY: nil,
            recordingFrame: recording,
            size: size,
            margin: margin
        )
        #expect(origin == KeyPressOverlayPlacement.defaultOrigin(
            recordingFrame: recording,
            size: size,
            margin: margin
        ))
    }

    @Test("Clamp keeps the HUD inside the recording frame")
    func clampKeepsHUDInside() {
        let outside = CGRect(
            x: recording.maxX + 50,
            y: recording.minY - 80,
            width: size.width,
            height: size.height
        )
        let clamped = KeyPressOverlayPlacement.clampedFrame(
            outside,
            in: recording,
            margin: margin
        )
        #expect(clamped.minX >= recording.minX + margin)
        #expect(clamped.minY >= recording.minY + margin)
        #expect(clamped.maxX <= recording.maxX - margin + 0.001)
        #expect(clamped.maxY <= recording.maxY - margin + 0.001)
    }

    @Test("Oversized HUD is fitted inside a tiny recording frame")
    func oversizedHUDFitsTinyRecording() {
        let tinyRecording = CGRect(x: 40, y: 80, width: 72, height: 36)
        let oversized = CGRect(x: -200, y: 500, width: 180, height: 64)

        let clamped = KeyPressOverlayPlacement.clampedFrame(
            oversized,
            in: tinyRecording,
            margin: margin
        )

        #expect(clamped.minX >= tinyRecording.minX - 0.001)
        #expect(clamped.minY >= tinyRecording.minY - 0.001)
        #expect(clamped.maxX <= tinyRecording.maxX + 0.001)
        #expect(clamped.maxY <= tinyRecording.maxY + 0.001)
    }

    @Test("Offset round-trips against the recording frame")
    func offsetRoundTrip() {
        let windowOrigin = CGPoint(x: recording.minX + 33, y: recording.minY + 44)
        let off = KeyPressOverlayPlacement.offset(
            windowOrigin: windowOrigin,
            recordingFrame: recording
        )
        #expect(off.x == 33)
        #expect(off.y == 44)
        let restored = KeyPressOverlayPlacement.origin(
            savedOffsetX: off.x,
            savedOffsetY: off.y,
            recordingFrame: recording,
            size: size,
            margin: margin
        )
        #expect(restored.x == windowOrigin.x)
        #expect(restored.y == windowOrigin.y)
    }
}
