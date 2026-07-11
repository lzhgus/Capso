import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Capture chrome layout")
struct CaptureChromeLayoutTests {
    @Test("All-in-One side rail starts compact regardless of selection height")
    func sideRailStartsCompact() {
        #expect(CaptureChromeLayout.startsWithCompactSideRail)
    }

    @Test("Annotation toolbar density follows available width")
    func annotationDensity() {
        #expect(CaptureChromeLayout.annotationDensity(for: 360) == .mini)
        #expect(CaptureChromeLayout.annotationDensity(for: 700) == .compact)
        #expect(CaptureChromeLayout.annotationDensity(for: 1_000) == .regular)
    }

    @Test("Density thresholds are stable at their boundaries")
    func densityBoundaries() {
        #expect(CaptureChromeLayout.annotationDensity(for: 479) == .mini)
        #expect(CaptureChromeLayout.annotationDensity(for: 480) == .compact)
        #expect(CaptureChromeLayout.annotationDensity(for: 839) == .compact)
        #expect(CaptureChromeLayout.annotationDensity(for: 840) == .regular)
    }
}
