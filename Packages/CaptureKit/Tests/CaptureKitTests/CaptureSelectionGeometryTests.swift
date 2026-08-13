import Testing
import CoreGraphics
@testable import CaptureKit

@Suite("CaptureSelectionGeometry")
struct CaptureSelectionGeometryTests {
    private let bounds = CGRect(x: 0, y: 0, width: 500, height: 360)
    private let minSize = CGSize(width: 40, height: 30)

    @Test("Moving a selection clamps it inside the screen bounds")
    func moveClampsInsideBounds() {
        let rect = CGRect(x: 420, y: 300, width: 70, height: 50)

        let moved = CaptureSelectionGeometry.move(
            rect,
            by: CGVector(dx: 80, dy: 90),
            in: bounds
        )

        #expect(moved == CGRect(x: 430, y: 310, width: 70, height: 50))
    }

    @Test("Resizing from a corner expands toward the pointer")
    func resizeCornerTowardPointer() {
        let rect = CGRect(x: 100, y: 90, width: 120, height: 80)

        let resized = CaptureSelectionGeometry.resize(
            rect,
            handle: .topRight,
            to: CGPoint(x: 270, y: 230),
            in: bounds,
            minSize: minSize
        )

        #expect(resized == CGRect(x: 100, y: 90, width: 170, height: 140))
    }

    @Test("Resizing keeps the minimum size")
    func resizePreservesMinimumSize() {
        let rect = CGRect(x: 100, y: 90, width: 120, height: 80)

        let resized = CaptureSelectionGeometry.resize(
            rect,
            handle: .left,
            to: CGPoint(x: 210, y: 130),
            in: bounds,
            minSize: minSize
        )

        #expect(resized == CGRect(x: 180, y: 90, width: 40, height: 80))
    }

    @Test("Creating a selection normalizes drag direction and clamps to bounds")
    func createNormalizesAndClamps() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 240, y: 180),
            to: CGPoint(x: -20, y: 390),
            in: bounds,
            minSize: minSize
        )

        #expect(created == CGRect(x: 0, y: 180, width: 240, height: 180))
    }

    @Test("Hit testing prefers handles before moving the body")
    func hitTestingPrefersHandles() {
        let rect = CGRect(x: 100, y: 90, width: 120, height: 80)

        let corner = CaptureSelectionGeometry.hitTarget(
            at: CGPoint(x: 219, y: 169),
            selectionRect: rect,
            hitSlop: 12
        )
        let body = CaptureSelectionGeometry.hitTarget(
            at: CGPoint(x: 150, y: 120),
            selectionRect: rect,
            hitSlop: 12
        )
        let outside = CaptureSelectionGeometry.hitTarget(
            at: CGPoint(x: 20, y: 20),
            selectionRect: rect,
            hitSlop: 12
        )

        #expect(corner == .resize(.topRight))
        #expect(body == .move)
        #expect(outside == nil)
    }

    @Test("Asymmetric hit testing keeps the resize zone thin inside the selection")
    func asymmetricHitTestingKeepsInnerZoneThin() {
        let rect = CGRect(x: 100, y: 90, width: 120, height: 80)

        func target(at point: CGPoint) -> CaptureSelectionHitTarget? {
            CaptureSelectionGeometry.hitTarget(
                at: point,
                selectionRect: rect,
                innerSlop: 3,
                outerSlop: 12
            )
        }

        // 10pt inside the top edge: belongs to the body (annotation), not resize.
        #expect(target(at: CGPoint(x: 160, y: rect.maxY - 10)) == .move)
        // 10pt inside a corner: still the body, not a corner resize.
        #expect(target(at: CGPoint(x: rect.minX + 10, y: rect.maxY - 10)) == .move)
        // Pressing right on the border resizes.
        #expect(target(at: CGPoint(x: 160, y: rect.maxY - 1)) == .resize(.top))
        #expect(target(at: CGPoint(x: rect.minX + 1, y: rect.maxY - 1)) == .resize(.topLeft))
        // The outside reach stays generous.
        #expect(target(at: CGPoint(x: 160, y: rect.maxY + 10)) == .resize(.top))
        #expect(target(at: CGPoint(x: rect.minX - 10, y: rect.maxY + 10)) == .resize(.topLeft))
        // Far outside hits nothing.
        #expect(target(at: CGPoint(x: 160, y: rect.maxY + 20)) == nil)
    }

    @Test("Symmetric hitSlop matches the asymmetric form with equal slops")
    func symmetricHitSlopMatchesAsymmetricForm() {
        let rect = CGRect(x: 100, y: 90, width: 120, height: 80)
        let probes = [
            CGPoint(x: 110, y: 100),
            CGPoint(x: 219, y: 169),
            CGPoint(x: 160, y: 175),
            CGPoint(x: 160, y: 165),
            CGPoint(x: 95, y: 130),
            CGPoint(x: 150, y: 120),
            CGPoint(x: 20, y: 20),
        ]

        for probe in probes {
            let symmetric = CaptureSelectionGeometry.hitTarget(
                at: probe,
                selectionRect: rect,
                hitSlop: 12
            )
            let asymmetric = CaptureSelectionGeometry.hitTarget(
                at: probe,
                selectionRect: rect,
                innerSlop: 12,
                outerSlop: 12
            )

            #expect(symmetric == asymmetric)
        }
    }

    @Test("Fitting an aspect ratio keeps the selection centered")
    func fittingAspectRatioKeepsCenter() {
        let rect = CGRect(x: 100, y: 90, width: 200, height: 80)

        let fitted = CaptureSelectionGeometry.fit(
            rect,
            aspectRatio: 4.0 / 3.0,
            in: bounds,
            minSize: minSize
        )

        #expect(fitted == CGRect(x: 100, y: 55, width: 200, height: 150))
    }

    @Test("Aspect ratio resize from the top edge keeps the bottom edge anchored")
    func aspectRatioTopEdgeResizeKeepsBottomAnchored() {
        let rect = CGRect(x: 100, y: 100, width: 120, height: 120)

        let resized = CaptureSelectionGeometry.resize(
            rect,
            handle: .top,
            to: CGPoint(x: 160, y: 260),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(resized == CGRect(x: 80, y: 100, width: 160, height: 160))
    }

    @Test("Aspect ratio resize from the right edge keeps the left edge anchored")
    func aspectRatioRightEdgeResizeKeepsLeftAnchored() {
        let rect = CGRect(x: 100, y: 100, width: 120, height: 120)

        let resized = CaptureSelectionGeometry.resize(
            rect,
            handle: .right,
            to: CGPoint(x: 260, y: 160),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(resized == CGRect(x: 100, y: 80, width: 160, height: 160))
    }

    @Test("Aspect ratio corner resize keeps the opposite corner anchored")
    func aspectRatioCornerResizeKeepsOppositeCornerAnchored() {
        let rect = CGRect(x: 100, y: 100, width: 120, height: 120)

        let resized = CaptureSelectionGeometry.resize(
            rect,
            handle: .topRight,
            to: CGPoint(x: 260, y: 280),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(resized == CGRect(x: 100, y: 100, width: 180, height: 180))
    }

    @Test("Aspect ratio edge resize clamps before crossing screen bounds")
    func aspectRatioEdgeResizeClampsBeforeCrossingBounds() {
        let rect = CGRect(x: 20, y: 100, width: 120, height: 120)

        let resized = CaptureSelectionGeometry.resize(
            rect,
            handle: .top,
            to: CGPoint(x: 80, y: 360),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(resized == CGRect(x: 0, y: 100, width: 160, height: 160))
    }

    @Test("Creating an aspect ratio selection keeps the drag start anchored")
    func aspectRatioCreateKeepsDragStartAnchored() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 230, y: 170),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(created == CGRect(x: 100, y: 100, width: 130, height: 130))
    }

    @Test("Centered create keeps the click as the square's midpoint")
    func centeredCreateKeepsClickAsMidpoint() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 180, y: 140),
            to: CGPoint(x: 300, y: 200),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1,
            centered: true
        )

        #expect(created == CGRect(x: 60, y: 20, width: 240, height: 240))
        #expect(created.midX == 180)
        #expect(created.midY == 140)
    }

    @Test("Centered create near an edge shrinks without sliding the center")
    func centeredCreateNearEdgeShrinksWithoutSliding() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 50, y: 50),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1,
            centered: true
        )

        #expect(created == CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(created.midX == 10)
        #expect(created.midY == 10)
        #expect(bounds.contains(created))
    }

    @Test("Centered create with no movement stays empty at the click")
    func centeredCreateWithoutMovementStaysAtClick() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 100, y: 100),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1,
            centered: true
        )

        #expect(created == CGRect(x: 100, y: 100, width: 0, height: 0))
    }

    @Test("Centered false still anchors the aspect-ratio create at the drag start")
    func centeredFalseKeepsDragStartAnchored() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 230, y: 170),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1,
            centered: false
        )

        #expect(created == CGRect(x: 100, y: 100, width: 130, height: 130))
    }

    @Test("Fixed size presets stay inside bounds")
    func fixedSizePresetStaysInsideBounds() {
        let fixed = CaptureSelectionGeometry.fixedSize(
            CGSize(width: 300, height: 200),
            centeredAt: CGPoint(x: 480, y: 340),
            in: bounds
        )

        #expect(fixed == CGRect(x: 200, y: 160, width: 300, height: 200))
    }

    // MARK: - Shift-to-square aspect ratio resolution

    @Test("Without square lock a free drag keeps no aspect ratio")
    func resolverFreeDragHasNoRatio() {
        #expect(CaptureSelectionGeometry.selectionAspectRatio(presetRatio: nil, squareLock: false) == nil)
    }

    @Test("Without square lock an active preset ratio passes through")
    func resolverPresetRatioPassesThrough() {
        let preset: CGFloat = 16.0 / 9.0
        #expect(CaptureSelectionGeometry.selectionAspectRatio(presetRatio: preset, squareLock: false) == preset)
    }

    @Test("Square lock forces a 1:1 ratio with no preset")
    func resolverSquareLockForcesOneToOne() {
        #expect(CaptureSelectionGeometry.selectionAspectRatio(presetRatio: nil, squareLock: true) == 1)
    }

    @Test("Square lock overrides an active preset ratio")
    func resolverSquareLockOverridesPreset() {
        #expect(CaptureSelectionGeometry.selectionAspectRatio(presetRatio: 16.0 / 9.0, squareLock: true) == 1)
    }

    @Test("A square-locked up-left drag still produces a square")
    func squareLockUpLeftDragIsSquare() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 200, y: 200),
            to: CGPoint(x: 120, y: 150),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(abs(created.width - created.height) < 1e-6)
        #expect(created.width > 0)
        #expect(bounds.contains(created))
    }

    @Test("A tiny square-locked drag respects the minimum size and stays square")
    func squareLockTinyDragRespectsMinimum() {
        let created = CaptureSelectionGeometry.rect(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 105, y: 102),
            in: bounds,
            minSize: minSize,
            aspectRatio: 1
        )

        #expect(abs(created.width - created.height) < 1e-6)
        #expect(created.width >= minSize.width)
    }
}
