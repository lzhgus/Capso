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
        #expect(CaptureChromeLayout.annotationDensity(for: 999) == .compact)
        #expect(CaptureChromeLayout.annotationDensity(for: 1_000) == .regular)
    }

    @Test("Annotation toolbar height depends on density and overflow, not the active tool")
    func annotationToolbarHeight() {
        #expect(CaptureChromeLayout.annotationToolbarHeight(density: .mini, showsOverflow: false) == 58)
        #expect(CaptureChromeLayout.annotationToolbarHeight(density: .mini, showsOverflow: true) == 102)
        #expect(CaptureChromeLayout.annotationToolbarHeight(density: .compact, showsOverflow: false) == 58)
        #expect(CaptureChromeLayout.annotationToolbarHeight(density: .compact, showsOverflow: true) == 102)
        #expect(CaptureChromeLayout.annotationToolbarHeight(density: .regular, showsOverflow: false) == 58)
        #expect(CaptureChromeLayout.annotationToolbarHeight(density: .regular, showsOverflow: true) == 58)
    }

    @Test("Only regular density renders text effects inline")
    func inlineTextEffects() {
        #expect(!CaptureChromeLayout.showsInlineTextEffects(for: .mini))
        #expect(!CaptureChromeLayout.showsInlineTextEffects(for: .compact))
        #expect(CaptureChromeLayout.showsInlineTextEffects(for: .regular))
    }
}
