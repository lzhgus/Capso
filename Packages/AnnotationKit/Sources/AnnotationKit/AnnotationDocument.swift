// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationDocument.swift
import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class AnnotationDocument {
    public private(set) var imageSize: CGSize
    public private(set) var objects: [any AnnotationObject] = []
    public private(set) var selectedObjectID: ObjectID?
    public private(set) var cropRect: CGRect?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private struct Snapshot {
        let objects: [any AnnotationObject]
        let cropRect: CGRect?
        let imageSize: CGSize
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(imageSize: CGSize) {
        self.imageSize = imageSize
    }

    public func addObject(_ object: any AnnotationObject) {
        pushUndo()
        objects.append(object)
        selectedObjectID = object.id
    }

    public func removeObject(id: ObjectID) {
        pushUndo()
        objects.removeAll { $0.id == id }
        if selectedObjectID == id { selectedObjectID = nil }
    }

    public func removeSelected() {
        guard let id = selectedObjectID else { return }
        removeObject(id: id)
    }

    public func selectObject(id: ObjectID?) {
        selectedObjectID = id
    }

    public func clearSelection() {
        selectedObjectID = nil
    }

    public var selectedObject: (any AnnotationObject)? {
        guard let id = selectedObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    public func objectAt(point: CGPoint, threshold: CGFloat = 8) -> (any AnnotationObject)? {
        for object in objects.reversed() {
            if object.hitTest(point: point, threshold: threshold) {
                return object
            }
        }
        return nil
    }

    public func moveObject(id: ObjectID, by delta: CGSize) {
        guard let obj = objects.first(where: { $0.id == id }) else { return }
        obj.move(by: delta)
    }

    public func beginDrag() {
        pushUndo()
    }

    public func setCropRect(_ rect: CGRect?) {
        pushUndo()
        cropRect = rect
    }

    /// Called after the crop editor replaces the working image (e.g. after
    /// rotate + commit). Updates `imageSize`, clears any stored crop rect
    /// (coordinates are no longer meaningful), and pushes an undo snapshot.
    /// Callers are expected to avoid calling this when `objects` is non-empty
    /// — the annotations' coordinates would be invalidated.
    public func replaceImage(size: CGSize) {
        pushUndo()
        imageSize = size
        cropRect = nil
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(objects: objects.map { $0.copy() }, cropRect: cropRect, imageSize: imageSize)
    }

    private func apply(_ snapshot: Snapshot) {
        objects = snapshot.objects
        cropRect = snapshot.cropRect
        imageSize = snapshot.imageSize
        selectedObjectID = nil
    }

    private func pushUndo() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot)
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot)
    }
}
