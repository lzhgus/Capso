// Packages/EditorKit/Tests/EditorKitTests/RecordingProjectTests.swift

import Testing
import Foundation
@testable import EditorKit

// MARK: - Helpers

private func makeProject(
    duration: TimeInterval = 60.0,
    trimRegions: [TrimRegion] = [],
    zoomSegments: [ZoomSegment] = [],
    showsCursor: Bool = true
) -> RecordingProject {
    RecordingProject(
        sourceVideoURL: URL(fileURLWithPath: "/tmp/test.mov"),
        showsCursor: showsCursor,
        videoDuration: duration,
        videoSize: CGSize(width: 1920, height: 1080),
        recordingAreaSize: CGSize(width: 1920, height: 1080),
        trimRegions: trimRegions,
        zoomSegments: zoomSegments
    )
}

// MARK: - RecordingProject Suite

@Suite("RecordingProject")
struct RecordingProjectTests {

    @Test("Round-trip JSON encode/decode")
    func jsonRoundTrip() throws {
        let original = makeProject(duration: 42.5)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try original.save(to: url)
        let loaded = try RecordingProject.load(from: url)

        #expect(loaded.id == original.id)
        #expect(loaded.videoDuration == original.videoDuration)
        #expect(loaded.videoSize.width == original.videoSize.width)
        #expect(loaded.videoSize.height == original.videoSize.height)
        #expect(loaded.sourceVideoURL == original.sourceVideoURL)
        #expect(loaded.showsCursor == original.showsCursor)
        #expect(loaded.trimRegions.count == original.trimRegions.count)
        #expect(loaded.zoomSegments.count == original.zoomSegments.count)
    }

    @Test("cursor visibility round-trips through JSON")
    func cursorVisibilityRoundTrip() throws {
        let original = makeProject(showsCursor: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordingProject.self, from: data)
        #expect(decoded.showsCursor == false)
    }

    @Test("legacy JSON without cursor visibility defaults to true")
    func legacyJSONDefaultsCursorVisibility() throws {
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "sourceVideoURL": "file:///tmp/test.mov",
          "videoDuration": 12,
          "videoSizeWidth": 1920,
          "videoSizeHeight": 1080,
          "recordingAreaWidth": 1920,
          "recordingAreaHeight": 1080,
          "trimRegions": [],
          "zoomSegments": [],
          "backgroundStyle": {
            "enabled": false,
            "colorType": "solid",
            "solidColor": { "red": 0.2, "green": 0.2, "blue": 0.2, "alpha": 1 },
            "gradientFrom": { "red": 0, "green": 0, "blue": 0, "alpha": 1 },
            "gradientTo": { "red": 0.2, "green": 0.2, "blue": 0.2, "alpha": 1 },
            "gradientAngle": 135,
            "padding": 20,
            "cornerRadius": 12,
            "shadowEnabled": true,
            "shadowRadius": 15,
            "shadowOpacity": 0.5
          },
          "cursorSmoothing": {
            "enabled": true,
            "stiffness": 120,
            "damping": 14,
            "mass": 1
          },
          "createdAt": "2026-04-18T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingProject.self, from: legacyJSON)
        #expect(decoded.showsCursor == true)
    }

    @Test("effectiveDuration subtracts trim regions")
    func effectiveDurationSubtractsTrim() {
        let trims = [
            TrimRegion(startTime: 0, endTime: 5),   // 5s
            TrimRegion(startTime: 20, endTime: 25),  // 5s
        ]
        let project = makeProject(duration: 60.0, trimRegions: trims)
        #expect(project.effectiveDuration == 50.0)
    }

    @Test("effectiveDuration never goes negative")
    func effectiveDurationClampedToZero() {
        let trims = [TrimRegion(startTime: 0, endTime: 100)]
        let project = makeProject(duration: 30.0, trimRegions: trims)
        #expect(project.effectiveDuration == 0.0)
    }

    @Test("effectiveDuration with no trims equals videoDuration")
    func effectiveDurationNoTrims() {
        let project = makeProject(duration: 120.0)
        #expect(project.effectiveDuration == 120.0)
    }
}

// MARK: - TrimRegion Suite

@Suite("TrimRegion")
struct TrimRegionTests {

    @Test("duration computed correctly")
    func duration() {
        let region = TrimRegion(startTime: 5.0, endTime: 15.5)
        #expect(region.duration == 10.5)
    }

    @Test("id defaults to unique UUID")
    func uniqueIDs() {
        let a = TrimRegion(startTime: 0, endTime: 1)
        let b = TrimRegion(startTime: 0, endTime: 1)
        #expect(a.id != b.id)
    }
}

// MARK: - ZoomSegment Suite

@Suite("ZoomSegment")
struct ZoomSegmentTests {

    @Test("defaults to followCursor and 1.5x zoom")
    func defaults() {
        let seg = ZoomSegment(startTime: 2.0, endTime: 8.0)
        #expect(seg.zoomLevel == 1.5)
        #expect(seg.focusMode == .followCursor)
    }

    @Test("manual focus mode stores correct coordinates")
    func manualFocusMode() {
        let seg = ZoomSegment(
            startTime: 0,
            endTime: 5,
            zoomLevel: 2.0,
            focusMode: .manual(x: 0.3, y: 0.7)
        )
        if case .manual(let x, let y) = seg.focusMode {
            #expect(x == 0.3)
            #expect(y == 0.7)
        } else {
            Issue.record("Expected .manual focus mode")
        }
    }

    @Test("ZoomSegment manual focus mode encodes/decodes correctly")
    func manualFocusModeRoundTrip() throws {
        let seg = ZoomSegment(
            startTime: 1.0,
            endTime: 4.0,
            zoomLevel: 3.0,
            focusMode: .manual(x: 0.5, y: 0.25)
        )
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(ZoomSegment.self, from: data)
        #expect(decoded.zoomLevel == seg.zoomLevel)
        #expect(decoded.focusMode == seg.focusMode)
    }

    @Test("duration computed correctly")
    func duration() {
        let seg = ZoomSegment(startTime: 3.0, endTime: 9.0)
        #expect(seg.duration == 6.0)
    }

    @Test("decodes legacy JSON without source key as .manual")
    func legacyJSONDecodesAsManual() throws {
        // JSON produced before Phase 2.1 — no `source` key.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "startTime": 1.0,
          "endTime": 4.0,
          "zoomLevel": 1.5,
          "focusMode": { "followCursor": {} }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ZoomSegment.self, from: legacyJSON)
        #expect(decoded.source == .manual)
        #expect(decoded.startTime == 1.0)
        #expect(decoded.endTime == 4.0)
    }

    @Test("defaults to .manual source when not specified")
    func defaultSourceIsManual() {
        let seg = ZoomSegment(startTime: 0, endTime: 3)
        #expect(seg.source == .manual)
    }
}

// MARK: - BackgroundStyle Suite

@Suite("BackgroundStyle")
struct BackgroundStyleTests {

    @Test("default background style has expected values")
    func defaultValues() {
        let style = BackgroundStyle.default
        #expect(style.enabled == false)
        #expect(style.colorType == .solid)
        #expect(style.padding == 20.0)
        #expect(style.cornerRadius == 12.0)
        #expect(style.shadowEnabled == true)
        #expect(style.shadowRadius == 15.0)
        #expect(style.shadowOpacity == 0.5)
    }

    @Test("CodableColor static presets have correct channels")
    func colorPresets() {
        let white = CodableColor.white
        #expect(white.red == 1.0)
        #expect(white.green == 1.0)
        #expect(white.blue == 1.0)
        #expect(white.alpha == 1.0)

        let black = CodableColor.black
        #expect(black.red == 0.0)
        #expect(black.green == 0.0)
        #expect(black.blue == 0.0)

        let darkGray = CodableColor.darkGray
        #expect(darkGray.red == 0.2)
        #expect(darkGray.green == 0.2)
        #expect(darkGray.blue == 0.2)
    }

    @Test("BackgroundStyle round-trips through JSON")
    func jsonRoundTrip() throws {
        let style = BackgroundStyle(
            enabled: true,
            colorType: .gradient,
            solidColor: .white,
            gradientFrom: .black,
            gradientTo: .white,
            gradientAngle: 90.0,
            padding: 40.0,
            cornerRadius: 8.0,
            shadowEnabled: false,
            shadowRadius: 0.0,
            shadowOpacity: 0.0
        )
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BackgroundStyle.self, from: data)
        #expect(decoded.enabled == style.enabled)
        #expect(decoded.colorType == style.colorType)
        #expect(decoded.gradientAngle == style.gradientAngle)
        #expect(decoded.shadowEnabled == style.shadowEnabled)
    }

    @Test("BackgroundStyle corner radius clamps to the editor max")
    func cornerRadiusClamp() {
        // Frame 300×120 → geometric cap = 60. With the editor max also at 60,
        // a radius of 400 should be clamped to the smaller of the two = 60.
        let style = BackgroundStyle(cornerRadius: 400)
        let clamped = style.clampedCornerRadius(for: CGSize(width: 300, height: 120))
        #expect(clamped == min(BackgroundStyle.maxCornerRadius, 60.0))
    }

    @Test("BackgroundStyle corner radius clamps below the geometric cap")
    func cornerRadiusClampsToGeometry() {
        // Frame 60×40 → geometric cap = 20, well below the editor max.
        // The clamp should honour the smaller (geometric) limit.
        let style = BackgroundStyle(cornerRadius: 400)
        let clamped = style.clampedCornerRadius(for: CGSize(width: 60, height: 40))
        #expect(clamped == 20)
    }
}

// MARK: - CursorSmoothingConfig Suite

@Suite("CursorSmoothingConfig")
struct CursorSmoothingConfigTests {

    @Test("smooth preset is the default init")
    func smoothPreset() {
        let smooth = CursorSmoothingConfig.smooth
        let defaultInit = CursorSmoothingConfig()
        #expect(smooth.stiffness == defaultInit.stiffness)
        #expect(smooth.damping == defaultInit.damping)
        #expect(smooth.mass == defaultInit.mass)
        #expect(smooth.enabled == defaultInit.enabled)
    }

    @Test("snappy preset has higher stiffness than smooth")
    func snappyHigherStiffness() {
        #expect(CursorSmoothingConfig.snappy.stiffness > CursorSmoothingConfig.smooth.stiffness)
    }

    @Test("floaty preset has lower stiffness than smooth")
    func floatyLowerStiffness() {
        #expect(CursorSmoothingConfig.floaty.stiffness < CursorSmoothingConfig.smooth.stiffness)
    }

    @Test("floaty preset has higher mass than smooth")
    func floatyHigherMass() {
        #expect(CursorSmoothingConfig.floaty.mass > CursorSmoothingConfig.smooth.mass)
    }

    @Test("snappy config maps back to snappy preset")
    func snappyPresetLookup() {
        #expect(CursorSmoothingConfig.snappy.preset == .snappy)
    }

    @Test("preset lookup ignores enabled flag")
    func presetLookupIgnoresEnabledFlag() {
        var config = CursorSmoothingConfig.floaty
        config.enabled = false
        #expect(config.preset == .floaty)
    }
}

// MARK: - FrameTransform Suite

@Suite("FrameTransform")
struct FrameTransformTests {

    @Test("identity transform has scale 1.0 and zero translation")
    func identityValues() {
        let id = FrameTransform.identity
        #expect(id.scale == 1.0)
        #expect(id.translateX == 0.0)
        #expect(id.translateY == 0.0)
    }

    @Test("default init equals identity")
    func defaultInitEqualsIdentity() {
        #expect(FrameTransform() == FrameTransform.identity)
    }

    @Test("non-identity transforms are not equal to identity")
    func nonIdentityNotEqual() {
        let zoomed = FrameTransform(scale: 2.0, translateX: 0.1, translateY: -0.1)
        #expect(zoomed != FrameTransform.identity)
    }
}
