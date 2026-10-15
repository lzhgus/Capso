# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - Unreleased

### Added
- **Comprehensive Shortcut Conflict Resolution**:
  - Automatically detect and resolve conflicts when restoring an action to its default shortcut, cleanly clearing or resetting any other action that adopted that shortcut.
  - Keypad keycode normalization ensuring numeric keypad inputs (e.g. Keypad 1) and top-row keys correctly detect conflicts and equivalence.
  - Active conflict detection against macOS system hotkeys and application menu items with clear visual indicators and tooltips.
- **Global Shortcut Suppression During Recording**:
  - Suppressed all global hotkey triggers while a shortcut is actively being recorded in Preferences, preventing accidental captures or window changes during key input.
- **Unit Test Coverage**:
  - Added dedicated test suite (`ShortcutConflictTests`) covering default resolution, conflict reversion, and keypad normalization.
