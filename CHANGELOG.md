# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - Unreleased

### Added
- **Preferences Modernization & Layout Polish**:
  - Redesigned Preferences window matching macOS System Settings styling, including native title bar height, left-aligned title, unified toolbar navigation, and refined padding.
  - Native sidebar search indexing across all settings tabs (General, Screenshots, Recording, Shortcuts, Quick Access, OCR, Translation, Cloud Share, Permissions).
  - Search result selection automatically navigates to the matching tab, smoothly scrolls to the target setting, and triggers a gentle highlight pulse.
  - Polished empty search state with clear guidance and resilient multi-line layout in macOS sidebar lists.
- **Settings Shortcut Fix**:
  - Replaced standard SwiftUI `Settings` scene with `CommandGroup(replacing: .appSettings)` to ensure `⌘,` consistently opens Capso Preferences.
