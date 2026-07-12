# All-in-One Text Toolbar Responsive Design

## Goal

Keep the All-in-One annotation toolbar visually stable when Text is selected. Text-specific controls must remain discoverable without adding a second text-only row or creating a three-row toolbar when compact overflow is open.

## Problem

The current mini and compact layouts append a full-width `Fill / Outline / Trace` row whenever Text is active. Compact overflow adds another row between the primary tools and text effects. This creates two or three unrelated alignment systems inside one toolbar, leaves a large empty region beside the three text effects, and makes the toolbar height jump when the selected tool changes.

## Alternatives Considered

1. **Stable toolbar with Text Style popover (chosen):** keep mini and compact toolbars at their normal height and open the three text effects from one dedicated Style button.
2. **Redesigned secondary text row:** group effects into a centered segmented control. More discoverable, but still changes toolbar height and produces three rows with compact overflow.
3. **Detached text inspector:** move text settings into a second floating panel. Flexible but creates another window-placement and collision system.

The popover approach is the smallest coherent design and preserves direct access without making Text structurally different from every other annotation tool.

## Responsive Rules

### Mini: selection width below 480 points

- Toolbar remains 300 by 58 points.
- Show current Text glyph, current color, font-size value, Text Style button, and More button.
- Do not render a second text-effects row.

### Compact: selection width from 480 through 999 points

- Toolbar width continues to clamp to the existing 520–840-point range.
- Show the six primary tools, compact color/font-size status, Text Style button, and More button.
- More may add the existing overflow row for secondary tools, full colors, slider, and Undo/Redo.
- Text Style remains in the primary row; opening More never adds a third row.

### Regular: selection width 1,000 points or wider

- Keep the existing 1,000-point single-row toolbar.
- Keep the three text-effect icon toggles inline beside the font-size slider.
- Keep the complete tool set, color palette, and Undo/Redo visible.

## Text Style Popover

- The button uses the `textformat` symbol and an active accent background when any text effect is enabled.
- The popover contains three horizontal toggles with an icon and label:
  - **Background** — toggles the existing text fill color.
  - **Box** — toggles the existing text box outline.
  - **Stroke** — toggles the existing glyph stroke.
- Active effects use the same accent treatment as active toolbar tools.
- Each toggle updates the selected text immediately, persists the existing UserDefaults key, and retains its existing accessibility help.
- Switching away from Text dismisses the popover.

## Toolbar Sizing

- Selecting or editing Text must not change the toolbar frame height.
- Mini remains 58 points high.
- Compact remains 58 points high when collapsed and 102 points high when More is expanded.
- Regular remains 58 points high.
- Button hit targets remain fixed; icons and labels do not continuously scale with the selection.

## Architecture

- Extend the existing CaptureKit chrome policy with a pure toolbar-height function so Text cannot reintroduce a layout-dependent height adjustment.
- Keep text-effect state and behavior in `AllInOneAnnotationSession` unchanged.
- Replace `textEffectsRow` with one popover-producing SwiftUI control in `AllInOneAnnotationToolbarView`.
- Keep regular inline text-effect controls and the right-side All-in-One action rail unchanged.

## Accessibility

- The Style button exposes the label `Text Style` and indicates whether effects are enabled.
- Each popover toggle exposes its visible label and active state.
- Keyboard annotation shortcuts remain unchanged while text editing is inactive.

## Verification

- Unit-test toolbar heights for mini, compact collapsed, compact expanded, and regular densities.
- Verify selecting Text never changes the panel height at any density.
- Verify mini, compact, and regular layouts in the running app.
- Verify compact Text with More expanded has exactly two rows.
- Verify Background, Box, and Stroke update newly created and selected text.
- Verify switching away from Text dismisses the popover.
- Run CaptureKit and SharedKit tests and a full macOS app build.

## Non-Goals

- No change to text rendering, colors, font-size range, selection geometry, right-side actions, or annotation shortcuts.
- No detached inspector window.
- No continuous scaling of button hit targets or typography.
