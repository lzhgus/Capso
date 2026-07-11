# All-in-One Selection Polish Design

## Goal

Make the frozen All-in-One selection feel precise and calm at every selection size. The work should improve the selection chrome and size feedback without changing capture behavior, keyboard shortcuts, presets, or annotation tools.

## Priority and Alternatives

Three follow-up directions were considered:

1. **Selection polish (chosen):** refine the border, resize affordances, dimension feedback, and side-rail density. This affects every All-in-One use and directly addresses the roughness visible while resizing selections.
2. **Annotation toolbar consolidation:** unify the full editor, inline editor, and All-in-One annotation toolbars. This has broader consistency value but is a larger architectural and visual change.
3. **Recording controls polish:** refine pre-recording and in-recording status. This is valuable but applies to a lower-frequency workflow than screenshot selection.

Selection polish is the best next step because it is high-frequency, self-contained, and easy to evaluate visually.

## Interaction Design

### Selection Border

- Replace the thick L-shaped corner brackets and midpoint ticks with one crisp, continuous white border.
- Add eight compact circular resize handles for regular selections: four corners and four edge midpoints.
- For selections narrower or shorter than 80 points, show only the four corner handles so the chrome does not overwhelm the content.
- Fixed-size presets show the border and dimension HUD but no resize handles because the selection can only move.
- Keep the existing 26-point invisible hit targets and existing resize cursors. The visual handles must not make resizing harder.

### Dimension HUD

- Move the dimensions out of the narrow right rail and into a compact floating HUD attached to the selection.
- Use a single-line monospaced label such as `1140 × 564`.
- Prefer placement eight points above the selection's top-left corner. If there is not enough room above, place it just inside the top-left corner.
- Draw the border and resize handles after the HUD so the handles remain visible above an inside HUD on tiny selections.
- Keep the HUD visible while the All-in-One selection is active so size feedback remains discoverable before and during resizing.

### Side Rail

- Remove the stacked width / `x` / height card.
- Recalculate the rail height without the dimension card, making the default compact rail visibly shorter.
- Preserve Copy, Save, Pin, Close, and More exactly as they work now.

### Backdrop

- Reduce the outside dimming slightly so the selected content remains the dominant visual element without making the surrounding context disappear.

## Architecture

Add a small pure layout policy in CaptureKit for adaptive handle visibility and dimension-HUD placement. The AppKit overlay consumes that policy for drawing. Capture geometry, hit-testing, presets, and toolbar actions stay unchanged.

This keeps visual thresholds testable without moving drawing code out of the App target.

## Testing

- Unit-test the 80-point handle threshold on both axes.
- Unit-test HUD placement above the selection and its inside fallback near the top screen edge.
- Run the full CaptureKit and SharedKit test suites.
- Build the macOS app with Swift 6 strict concurrency checks.
- Manually verify small, medium, and large selections in the running app and capture screenshots for review.

## Non-Goals

- No new capture mode or confirmation step.
- No changes to annotation tools, Quick Access, presets, or keyboard shortcuts.
- No refactor of the three annotation toolbar implementations in this pass.
