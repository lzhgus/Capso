<!--
Thanks for contributing to Capso! A few quick reminders:

- Keep PRs focused — one feature or fix per PR.
- If you changed project.yml or added/removed source files, run `xcodegen generate`.
- Make sure the Debug build passes before pushing.
- For UI changes, please include a screenshot or screen recording (use Capso to capture it!).
-->

## What changed

<!-- A short description of what this PR does and *why*. -->

## Related issue

<!-- Link to the issue this PR addresses, if any. Use "Closes #123" or "Refs #123". -->

## Screenshots / recordings

<!-- Drag and drop media here for any UI change. -->

## Checklist

- [ ] `xcodegen generate` run if `project.yml` or source layout changed
- [ ] `xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug build` passes
- [ ] Tests for any touched package pass (`swift test --package-path Packages/<Kit>`)
- [ ] No new `TODO` / `FIXME` / debug prints left behind
- [ ] Code follows Swift 6.0 strict concurrency (`@MainActor`, `Sendable` where needed)
- [ ] I agree that my contribution is licensed under the MIT License per [CONTRIBUTING.md](../CONTRIBUTING.md#license)
