# Screenshot Filename Template Design

## Context

GitHub discussion #154 asks for screenshot filenames to be customizable. The motivating example is removing the `Capso Screenshot` prefix so screenshots can be named with only date and time.

Capso currently centralizes screenshot and recording filename generation in `SharedKit` via `FileNaming`. Autosave, history Save As, and recording export already call that utility, so the feature can stay small and avoid duplicating naming logic across coordinators.

Reference behavior:

- `macshot` has a full template formatter with screenshot and recording templates, live settings previews, reset buttons, token help, filesystem sanitization, byte-length caps, and reuse across local saves and uploads.
- `capcap` uses fixed timestamp-based names such as `capcap-yyMMdd-HHmmss.png` and does not expose filename templates.

## Goals

- Let users customize screenshot base filenames from Preferences.
- Keep the current default filename behavior for existing users.
- Keep extensions automatic so templates describe the base name only.
- Centralize rendering and sanitization in `SharedKit`.
- Show a live preview in Preferences so users can see the resulting filename before taking a screenshot.
- Add focused unit tests for template rendering and fallback behavior.

## Non-Goals

- Do not add directory/path templates.
- Do not let users include or override the file extension in the template.
- Do not add a full date-format mini-language.
- Do not change monthly folder behavior.
- Do not require custom templates for recordings in v1.
- Do not change upload naming unless a path already uses screenshot `FileNaming`.

## Template Syntax

Templates are plain strings with case-sensitive placeholder tokens. Unknown tokens remain visible in the rendered filename so typos are obvious.

Supported v1 tokens:

- `{date}`: `yyyy-MM-dd`
- `{time}`: `HH.mm.ss`, matching Capso's current time separator
- `{timestamp}`: `{date} at {time}`
- `{source}`: ` - <app>` when a source app is available, otherwise blank
- `{app}`: sanitized source app name, or blank when unavailable
- `{window}`: sanitized source window title, or blank when unavailable
- `{random}`: fresh 8-character lowercase base36 string

Default screenshot template:

```text
Capso Screenshot{source} {timestamp}
```

The `{source}` token preserves today's default output without leaving punctuation behind when the source app is unavailable:

```text
Capso Screenshot - Safari 2026-06-07 at 16.11.23.png
```

For user-authored templates, `{app}` renders only the sanitized app name. Users can choose their own separators or use `{source}` when they want the current default-style suffix:

```text
{date}-{time}
{app} {date} {time}
{timestamp}-{random}
```

## Sanitization And Fallback

The rendered base filename should be safe for macOS filesystems:

- Replace `/`, `:`, and NUL with `-`.
- Strip control characters.
- Trim leading and trailing whitespace/newlines.
- Trim trailing dots.
- Cap the base filename to a conservative UTF-8 byte length.

If the stored template is empty or renders to an empty filename, fall back to the default screenshot template. If that somehow still renders empty, use `Capso Screenshot`.

The extension is appended after sanitization based on the selected screenshot format.

## Preferences UI

Add a filename template row to Preferences > Export, near save location and monthly folders:

- Label: `Screenshot Filename`
- Monospaced text field bound to the persisted template.
- Small reset button restoring the default template.
- Small info/help control showing supported tokens.
- Live preview below the row, using a stable sample date, app, and window title.

The UI should save edits as the user types and should reset blank input to the default when editing ends.

## Storage

Add an `AppSettings` string property for the screenshot filename template. It should return the default template if no value is stored.

Do not migrate any existing setting because Capso does not currently have a legacy filename customization preference.

## Application Flow

Update screenshot save paths to pass `settings.screenshotFilenameTemplate` into `FileNaming`:

- Auto-save after capture.
- Save from pinned screenshot.
- Save As from screenshot history.

Keep recording filenames unchanged in v1, though the rendering API should be shaped so recording templates can reuse it later.

## Tests

Add `SharedKit` unit tests covering:

- Existing default screenshot and recording names still pass.
- A date/time-only template renders without the `Capso Screenshot` prefix.
- `{app}` and `{window}` are sanitized.
- `{source}` is blank when no source app is available and includes the default separator when one is available.
- Unknown tokens remain visible.
- Empty templates fall back to the default.
- Filenames keep the requested extension.
- `{random}` creates an 8-character lowercase base36 token.

## Open Questions

- Should recording templates be exposed in a follow-up? The shared rendering API can support it, but the discussion only requested screenshots.
- Should `{timestamp}` use `yyyy-MM-dd at HH.mm.ss` for Capso compatibility or `yyyy-MM-dd_HH.mm.ss` for compact filenames? v1 chooses compatibility.
