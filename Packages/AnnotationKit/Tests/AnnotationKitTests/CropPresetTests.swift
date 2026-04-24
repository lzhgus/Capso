// Packages/AnnotationKit/Tests/AnnotationKitTests/CropPresetTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("CropPreset")
struct CropPresetTests {
    @Test("Freeform has no ratio")
    func freeformNoRatio() {
        #expect(CropPreset.freeform.ratio(imageSize: CGSize(width: 800, height: 600)) == nil)
    }

    @Test("Original ratio matches image size")
    func originalRatio() {
        let ratio = CropPreset.original.ratio(imageSize: CGSize(width: 1920, height: 1080))
        let expected = 1920.0 / 1080.0
        #expect(abs(ratio! - expected) < 0.0001)
    }

    @Test("Fixed preset ratios")
    func fixedRatios() {
        let size = CGSize(width: 800, height: 600)
        #expect(CropPreset.square.ratio(imageSize: size) == 1.0)
        #expect(abs(CropPreset.ratio4x3.ratio(imageSize: size)! - 4.0 / 3.0) < 0.0001)
        #expect(abs(CropPreset.ratio16x9.ratio(imageSize: size)! - 16.0 / 9.0) < 0.0001)
        #expect(abs(CropPreset.ratio3x2.ratio(imageSize: size)! - 3.0 / 2.0) < 0.0001)
    }

    @Test("Display name")
    func displayName() {
        #expect(CropPreset.freeform.displayName == "Freeform")
        #expect(CropPreset.original.displayName == "Original Ratio")
        #expect(CropPreset.square.displayName == "1 : 1 (Square)")
        #expect(CropPreset.ratio4x3.displayName == "4 : 3")
        #expect(CropPreset.ratio16x9.displayName == "16 : 9")
        #expect(CropPreset.ratio3x2.displayName == "3 : 2")
    }

    @Test("allCases order")
    func allCasesOrder() {
        #expect(CropPreset.allCases == [.freeform, .original, .square, .ratio4x3, .ratio3x2, .ratio16x9])
    }
}
