// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationDocumentTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationDocument")
struct AnnotationDocumentTests {
    @Test("Add and remove objects")
    @MainActor
    func addRemove() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.objects.count == 1)
        doc.removeObject(id: arrow.id)
        #expect(doc.objects.count == 0)
    }

    @Test("Undo and redo add")
    @MainActor
    func undoRedo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.objects.count == 1)
        #expect(doc.canUndo)

        doc.undo()
        #expect(doc.objects.count == 0)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.objects.count == 1)
    }

    @Test("Selection")
    @MainActor
    func selection() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.selectObject(id: arrow.id)
        #expect(doc.selectedObjectID == arrow.id)
        doc.clearSelection()
        #expect(doc.selectedObjectID == nil)
    }

    @Test("cropRect starts nil")
    @MainActor
    func cropRectDefaultNil() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        #expect(doc.cropRect == nil)
    }

    @Test("setCropRect updates value and pushes undo")
    @MainActor
    func setCropRectUndo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let rect = CGRect(x: 100, y: 50, width: 400, height: 300)
        doc.setCropRect(rect)
        #expect(doc.cropRect == rect)
        #expect(doc.canUndo)

        doc.undo()
        #expect(doc.cropRect == nil)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.cropRect == rect)
    }

    @Test("setCropRect with nil clears the crop")
    @MainActor
    func clearCropRect() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.setCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        doc.setCropRect(nil)
        #expect(doc.cropRect == nil)
    }

    @Test("undo restores objects AND cropRect together")
    @MainActor
    func undoRestoresBothObjectsAndCrop() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 50, y: 50))
        doc.addObject(arrow)
        doc.setCropRect(CGRect(x: 10, y: 10, width: 100, height: 100))

        #expect(doc.objects.count == 1)
        #expect(doc.cropRect != nil)

        doc.undo()
        #expect(doc.objects.count == 1)
        #expect(doc.cropRect == nil)

        doc.undo()
        #expect(doc.objects.count == 0)
        #expect(doc.cropRect == nil)
    }
}
