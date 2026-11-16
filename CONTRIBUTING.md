# Contributing to Capso

Thanks for your interest in contributing to Capso! This document covers the development setup and contribution guidelines.

## Development Setup

### Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Swift 6.0+

### Getting Started

```bash
git clone https://github.com/lzhgus/Capso.git
cd Capso
xcodegen generate
open Capso.xcodeproj
```

Build and run with `Cmd+R` in Xcode. The app requires screen recording, camera, and microphone permissions.

### Running Tests

Each SPM package has independent tests:

```bash
swift test --package-path Packages/SharedKit
swift test --package-path Packages/AnnotationKit
swift test --package-path Packages/CaptureKit
swift test --package-path Packages/RecordingKit
swift test --package-path Packages/CameraKit
swift test --package-path Packages/OCRKit
swift test --package-path Packages/ExportKit
swift test --package-path Packages/EffectsKit
```

Or run all tests via Xcode:

```bash
xcodebuild test -project Capso.xcodeproj -scheme Capso
```

### Project Structure

Capso uses a modular architecture with 8 independent SPM packages. See [README.md](README.md#architecture) for the full breakdown.

**Key convention:** The `App/` target is a thin shell. Business logic belongs in the appropriate package under `Packages/`.

## Code Style

- **Swift 6.0 strict concurrency** is enforced. All UI coordinators are `@MainActor`.
- **No linter or formatter** is configured. Follow existing code patterns.
- Use `@preconcurrency import` for frameworks that haven't adopted Sendable.
- Types crossing actor boundaries must conform to `Sendable`.
- Prefer SwiftUI for new UI; use AppKit (`NSPanel`, `NSWindow`) for overlays and system-level UI.

## Making Changes

### Before You Start

1. Check [open issues](../../issues) for existing discussion
2. For large changes, open an issue first to discuss the approach
3. For small fixes (typos, bugs), feel free to submit a PR directly

### Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Run `xcodegen generate` if you modified `project.yml` or added/removed source files
5. Build successfully: `xcodebuild -project Capso.xcodeproj -scheme Capso build`
6. Run relevant package tests
7. Submit a PR with a clear description of what changed and why

### PR Guidelines

- Keep PRs focused — one feature or fix per PR
- Include screenshots/GIFs for UI changes
- Update relevant comments if behavior changes
- Don't mix refactoring with feature work

## Good First Issues

Look for issues labeled [`good first issue`](../../labels/good%20first%20issue) — these are designed to be approachable for new contributors.

Some areas that are particularly welcoming:
- Adding new annotation tools (see `Packages/AnnotationKit/`)
- Improving localization (currently EN + ZH-Hans)
- Writing tests for existing packages
- UI polish and accessibility improvements

## Architecture Notes

When adding features, consider which layer it belongs to:

| Layer | Location | Purpose |
|-------|----------|---------|
| Package | `Packages/[Kit]/` | Core logic, testable, no UI dependencies |
| Coordinator | `App/Sources/[Feature]/` | Orchestrates UI flow, owns windows/panels |
| View | `App/Sources/[Feature]/` | SwiftUI views and AppKit NSViews |

Packages should depend only on `SharedKit` and system frameworks. Never add cross-package dependencies between feature kits.

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers the project.
