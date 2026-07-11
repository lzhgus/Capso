# All-in-One Selection Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the heavy All-in-One selection brackets with adaptive circular handles, move size feedback into a floating HUD, and shorten the default side rail.

**Architecture:** Add a pure `CaptureSelectionChromeLayout` policy to CaptureKit for visible handles, dimension text, and HUD placement. Keep Core Graphics drawing in the existing AppKit overlay and keep all capture geometry and hit-testing unchanged.

**Tech Stack:** Swift 6.0, CoreGraphics, AppKit, Swift Testing, XcodeGen/Xcode build.

## Global Constraints

- Target macOS 15.0 or later.
- Preserve the existing 26-point resize hit targets, cursors, presets, capture actions, and shortcuts.
- Fixed-size presets must not display resize handles.
- Do not change Quick Access or annotation tool behavior in this pass.

---

### Task 1: Testable Selection Chrome Policy

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/CaptureSelectionChromeLayout.swift`
- Create: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureSelectionChromeLayoutTests.swift`

**Interfaces:**
- Produces: `CaptureSelectionChromeLayout.visibleHandles(for:isFixedSize:) -> [CaptureSelectionResizeHandle]`
- Produces: `CaptureSelectionChromeLayout.dimensionText(for:) -> String`
- Produces: `CaptureSelectionChromeLayout.dimensionHUDOrigin(selectionRect:hudSize:in:gap:insideInset:) -> CGPoint`, which tries above, then below, then inside the selection.

- [ ] **Step 1: Write failing policy tests**

```swift
import CoreGraphics
import Testing
@testable import CaptureKit

@Suite("Capture selection chrome layout")
struct CaptureSelectionChromeLayoutTests {
    @Test("Regular selections expose all eight resize handles")
    func regularHandles() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 320, height: 180),
            isFixedSize: false
        ).count == 8)
    }

    @Test("Small selections keep only corner handles")
    func smallHandles() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 79, height: 180),
            isFixedSize: false
        ) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
    }

    @Test("Fixed-size selections hide resize handles")
    func fixedHandles() {
        #expect(CaptureSelectionChromeLayout.visibleHandles(
            for: CGSize(width: 320, height: 180),
            isFixedSize: true
        ).isEmpty)
    }

    @Test("Dimension text uses the multiplication sign")
    func dimensionText() {
        #expect(CaptureSelectionChromeLayout.dimensionText(
            for: CGSize(width: 1_139.6, height: 563.7)
        ) == "1140 × 564")
    }

    @Test("HUD prefers above and falls below near the top edge")
    func hudPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let hud = CGSize(width: 92, height: 24)
        #expect(CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: CGRect(x: 100, y: 100, width: 500, height: 300),
            hudSize: hud,
            in: bounds
        ) == CGPoint(x: 100, y: 408))
        #expect(CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: CGRect(x: 100, y: 500, width: 500, height: 290),
            hudSize: hud,
            in: bounds
        ) == CGPoint(x: 100, y: 468))
    }

    @Test("Tiny selections at the top edge place the HUD below without overlap")
    func tinyTopEdgeHUDPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let hud = CGSize(width: 92, height: 24)
        let selection = CGRect(x: 100, y: 776, width: 120, height: 24)
        let origin = CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: selection,
            hudSize: hud,
            in: bounds
        )

        #expect(origin == CGPoint(x: 100, y: 744))
        #expect(CGRect(origin: origin, size: hud).maxY <= selection.minY)
    }

    @Test("HUD falls inside when neither outside placement fits")
    func insideHUDPlacement() {
        #expect(CaptureSelectionChromeLayout.dimensionHUDOrigin(
            selectionRect: CGRect(x: 100, y: 4, width: 500, height: 792),
            hudSize: CGSize(width: 92, height: 24),
            in: CGRect(x: 0, y: 0, width: 1_200, height: 800)
        ) == CGPoint(x: 110, y: 762))
    }
}
```

- [ ] **Step 2: Run the tests and verify the missing policy fails**

Run: `rtk test swift test --package-path Packages/CaptureKit --filter CaptureSelectionChromeLayoutTests`

Expected: FAIL because `CaptureSelectionChromeLayout` does not exist.

- [ ] **Step 3: Implement the minimal policy**

```swift
import CoreGraphics

public enum CaptureSelectionChromeLayout {
    public static let minimumEdgeHandleDimension: CGFloat = 80

    public static func visibleHandles(
        for selectionSize: CGSize,
        isFixedSize: Bool
    ) -> [CaptureSelectionResizeHandle] {
        guard !isFixedSize else { return [] }
        let corners: [CaptureSelectionResizeHandle] = [
            .topLeft, .topRight, .bottomRight, .bottomLeft,
        ]
        guard min(selectionSize.width, selectionSize.height) >= minimumEdgeHandleDimension else {
            return corners
        }
        return [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
    }

    public static func dimensionText(for selectionSize: CGSize) -> String {
        "\(max(1, Int(selectionSize.width.rounded()))) × \(max(1, Int(selectionSize.height.rounded())))"
    }

    public static func dimensionHUDOrigin(
        selectionRect: CGRect,
        hudSize: CGSize,
        in bounds: CGRect,
        gap: CGFloat = 8,
        insideInset: CGFloat = 10
    ) -> CGPoint {
        let clampedX = min(max(selectionRect.minX, bounds.minX), bounds.maxX - hudSize.width)
        let aboveY = selectionRect.maxY + gap
        if aboveY + hudSize.height <= bounds.maxY {
            return CGPoint(x: clampedX, y: aboveY)
        }
        let belowY = selectionRect.minY - gap - hudSize.height
        if belowY >= bounds.minY {
            return CGPoint(x: clampedX, y: belowY)
        }
        return CGPoint(
            x: min(max(selectionRect.minX + insideInset, bounds.minX), bounds.maxX - hudSize.width),
            y: min(max(selectionRect.maxY - hudSize.height - insideInset, bounds.minY), bounds.maxY - hudSize.height)
        )
    }
}
```

- [ ] **Step 4: Run the filtered and full CaptureKit tests**

Run: `rtk test swift test --package-path Packages/CaptureKit --filter CaptureSelectionChromeLayoutTests`

Expected: PASS.

Run: `rtk test swift test --package-path Packages/CaptureKit`

Expected: all CaptureKit tests pass.

### Task 2: AppKit Selection Chrome and Dimension HUD

**Files:**
- Modify: `App/Sources/Capture/CaptureAllInOneToolbarWindow.swift:590-620`
- Modify: `App/Sources/Capture/CaptureAllInOneToolbarWindow.swift:695-755`
- Modify: `App/Sources/Capture/CaptureAllInOneToolbarWindow.swift:1423-1545`

**Interfaces:**
- Consumes all three `CaptureSelectionChromeLayout` methods from Task 1.
- Preserves `CaptureSelectionGeometry.hitTarget`, `hitSlop`, and cursor behavior.

- [ ] **Step 1: Remove the rail dimension card and calculate exact rail contents**

Remove `railDimensionPill` from `sideRail`, delete that private view, and replace `preferredRailHeight` item construction with:

```swift
var itemHeights: [CGFloat] = []
if !isCompact || showsOverflow {
    itemHeights += Array(repeating: rowHeight, count: 7)
    itemHeights.append(dividerHeight)
    itemHeights.append(presetHeight)
}
itemHeights += Array(repeating: rowHeight, count: 4)
if isCompact {
    itemHeights.append(dividerHeight)
    itemHeights.append(rowHeight)
}
```

- [ ] **Step 2: Replace bracket drawing with the new border and handles**

In `drawSelectionChrome`, draw a subtle dark under-stroke, a 1.5-point white border, and one circular handle for each value returned by `visibleHandles`. Use a private `point(for:in:)` switch to map handles to corners and edge midpoints. Each handle is a 7-point white circle with a 1-point dark stroke and a soft black shadow.

- [ ] **Step 3: Draw the dimension HUD**

Add `drawDimensionHUD(in:selectionRect:)`. Measure `CaptureSelectionChromeLayout.dimensionText(for:)` with `NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)`, add 8-point horizontal and 5-point vertical padding, obtain the origin from `dimensionHUDOrigin`, then draw a rounded black 72%-opacity background, a 0.5-point white 18%-opacity stroke, and white text.

- [ ] **Step 4: Reduce backdrop opacity**

Change the outside fill from black at `0.38` opacity to `0.32` and leave the selected region clear.

- [ ] **Step 5: Build the full app**

Run: `rtk err xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug -derivedDataPath build/DerivedData build`

Expected: exit code 0 with no new errors.

### Task 3: Verification and Visual Review

**Files:**
- No source changes expected unless verification exposes a concrete defect.

- [ ] **Step 1: Run focused package suites**

Run in parallel:

```bash
rtk test swift test --package-path Packages/CaptureKit
rtk test swift test --package-path Packages/SharedKit
```

Expected: both suites pass.

- [ ] **Step 2: Check the patch**

Run: `rtk git diff --check`

Expected: no output and exit code 0.

- [ ] **Step 3: Launch one test instance**

Close existing Capso processes, launch `build/DerivedData/Build/Products/Debug/Capso.app`, and verify that only that executable remains running.

- [ ] **Step 4: Visually inspect three sizes**

Create small, medium, and large All-in-One selections. Confirm that small selections have four corner handles, regular selections have eight handles, fixed-size presets have no resize handles, the dimension HUD never leaves the screen, and the side rail does not overlap the annotation toolbar.

- [ ] **Step 5: Capture review screenshots**

Save screenshots under `/tmp/capso-all-in-one-selection-polish/` and include the small, medium, and large states in the handoff.
