# All-in-One Text Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep mini and compact All-in-One Text toolbars at a stable height and move Background, Box, and Stroke into a dedicated Text Style popover.

**Architecture:** Put density-dependent toolbar height in the existing pure CaptureKit chrome policy, then consume it from the AppKit panel frame. Keep text-effect state in `AllInOneAnnotationSession`; replace the compact-only text row with a SwiftUI popover while retaining regular inline controls.

**Tech Stack:** Swift 6.0, SwiftUI, AppKit, CoreGraphics, Swift Testing.

## Global Constraints

- Target macOS 15.0 or later.
- Mini is 300 by 58 points when collapsed.
- Compact is 58 points high when collapsed and 102 points high when More is expanded.
- Regular is 1,000 by 58 points.
- Selecting or editing Text must not add toolbar height.
- Preserve text rendering, font-size range, UserDefaults keys, annotation shortcuts, right-side actions, and selection geometry.

---

### Task 1: Testable Annotation Toolbar Height Policy

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/CaptureChromeLayout.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureChromeLayoutTests.swift`

**Interfaces:**
- Produces: `CaptureChromeLayout.annotationToolbarHeight(density:showsOverflow:) -> CGFloat`
- Produces: `CaptureChromeLayout.showsInlineTextEffects(for:) -> Bool`

- [ ] **Step 1: Write failing policy tests**

```swift
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
```

- [ ] **Step 2: Run the filtered tests and verify the missing APIs fail**

Run: `rtk test swift test --package-path Packages/CaptureKit --filter CaptureChromeLayoutTests`

Expected: FAIL because the two policy methods do not exist.

- [ ] **Step 3: Implement the minimal policy**

```swift
public static func annotationToolbarHeight(
    density: CaptureChromeDensity,
    showsOverflow: Bool
) -> CGFloat {
    switch density {
    case .mini, .compact:
        return showsOverflow ? 102 : 58
    case .regular:
        return 58
    }
}

public static func showsInlineTextEffects(for density: CaptureChromeDensity) -> Bool {
    density == .regular
}
```

- [ ] **Step 4: Run filtered and full CaptureKit tests**

Run: `rtk test swift test --package-path Packages/CaptureKit --filter CaptureChromeLayoutTests`

Expected: PASS.

Run: `rtk test swift test --package-path Packages/CaptureKit`

Expected: all CaptureKit tests pass.

### Task 2: Stable Text Toolbar and Style Popover

**Files:**
- Modify: `App/Sources/Capture/CaptureAllInOneAnnotationOverlay.swift:172-210`
- Modify: `App/Sources/Capture/CaptureAllInOneAnnotationOverlay.swift:586-990`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `CaptureChromeLayout.annotationToolbarHeight(density:showsOverflow:)`
- Consumes: `CaptureChromeLayout.showsInlineTextEffects(for:)`
- Preserves: `annotationTextFillEnabled`, `annotationTextOutlineEnabled`, and `annotationTextStrokeEnabled` UserDefaults keys.

- [ ] **Step 1: Make the panel frame independent of Text mode**

Delete the `showsTextOptions` height adjustment and calculate height with:

```swift
let height = CaptureChromeLayout.annotationToolbarHeight(
    density: density,
    showsOverflow: showsOverflow
)
```

Keep existing width calculations for mini, compact, and regular densities.

- [ ] **Step 2: Remove the compact text-effects row**

Delete both `if isFontSizeMode { textEffectsRow }` insertions from `adaptiveToolbar` and `miniToolbar`, then delete the unused `textEffectsRow` and `textEffectButton` helpers.

- [ ] **Step 3: Add stable Text Style state and placement**

Add:

```swift
@State private var showsTextStylePopover = false

private var hasActiveTextEffect: Bool {
    session.textFillEnabled || session.textOutlineEnabled || session.textStrokeEnabled
}
```

In mini, place `textStyleButton` after the font-size value and before More when `isFontSizeMode`.

In compact, place `textStyleButton` after `compactStatus` and before More when `isFontSizeMode`.

Regular continues to render `textEffectsInlineControls` inside `primaryControls` when `CaptureChromeLayout.showsInlineTextEffects(for: session.toolbarDensity)` is true.

- [ ] **Step 4: Implement the Text Style button and popover**

```swift
private var textStyleButton: some View {
    Button {
        showsTextStylePopover.toggle()
    } label: {
        Image(systemName: "textformat")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(buttonBackground(isActive: hasActiveTextEffect, isEnabled: true))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .help("Text Style")
    .accessibilityLabel(Text("Text Style"))
    .accessibilityValue(Text(hasActiveTextEffect ? "On" : "Off"))
    .popover(isPresented: $showsTextStylePopover, arrowEdge: .top) {
        textStylePopover
    }
}
```

The popover is one horizontal `HStack(spacing: 6)` with three 72-by-48 toggle buttons. Use `rectangle.fill` / Background, `rectangle` / Box, and `textformat` / Stroke. Each action must toggle its existing session property, persist its existing UserDefaults key, and call `session.updateSelectedStyle()`.

- [ ] **Step 5: Dismiss Text Style when Text mode ends**

Attach:

```swift
.onChange(of: isFontSizeMode) { _, isTextMode in
    if !isTextMode {
        showsTextStylePopover = false
    }
}
```

- [ ] **Step 6: Add localized labels**

Reuse the existing `Background` entry. Add `Box`, `Stroke`, and `Text Style` to `Localizable.xcstrings` with these translations:

| Key | ja | ko | zh-Hans |
|---|---|---|---|
| Box | ボックス | 상자 | 方框 |
| Stroke | ストローク | 외곽선 | 描边 |
| Text Style | テキストスタイル | 텍스트 스타일 | 文字样式 |

- [ ] **Step 7: Build the app**

Run: `rtk err xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug -derivedDataPath build/DerivedData build`

Expected: exit code 0 with no new errors.

### Task 3: Regression and Visual Verification

**Files:**
- No source changes expected unless verification exposes a concrete defect.

- [ ] **Step 1: Run package suites**

Run in parallel:

```bash
rtk test swift test --package-path Packages/CaptureKit
rtk test swift test --package-path Packages/SharedKit
```

Expected: both suites pass.

- [ ] **Step 2: Check branch state**

Run: `rtk git diff --check` and `rtk git status --short`.

Expected: clean output.

- [ ] **Step 3: Launch one current test instance**

Close other Capso processes and launch `build/DerivedData/Build/Products/Debug/Capso.app`. Verify only that executable remains running.

- [ ] **Step 4: Verify mini, compact, and regular Text layouts**

- Mini below 480 points: one 58-point row with Text, color, size, Style, and More.
- Compact from 480 through 999 points: one 58-point collapsed row; More produces exactly two rows and 102-point height.
- Regular from 1,000 points: one 58-point row with inline text effects.
- Switching between Text and other tools never changes the frame height.

- [ ] **Step 5: Verify effect behavior**

Create and select text, then toggle Background, Box, and Stroke. Confirm immediate visual updates, persistence, active state, popover dismissal on tool switch, and VoiceOver labels.

- [ ] **Step 6: Capture review screenshots**

Save mini, compact, compact-expanded, regular, and open-popover screenshots under `/tmp/capso-text-toolbar-polish/`.
