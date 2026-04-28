# Continuous Integration

This repository uses GitHub Actions for pull request and `main` branch validation.

Baseline targets macOS 26, so CI runs on GitHub's `macos-26` hosted runner.

The CI workflow:
- Installs Tuist with Homebrew.
- Lints release scripts with `bash -n`.
- Generates the Xcode project.
- Builds the Debug app with code signing disabled.
- Runs unit tests on `platform=macOS`.

CI intentionally does not launch the menubar app. Installed-app smoke validation still requires the local desktop session.

The local equivalent for build and test validation is:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild -project Baseline.xcodeproj -scheme Baseline -configuration Debug -destination 'platform=macOS' -derivedDataPath .DerivedData build
xcodebuild -project Baseline.xcodeproj -scheme Baseline -destination 'platform=macOS' -derivedDataPath .DerivedData test
```

For full preview validation, run:

```bash
scripts/validate-preview.sh 0.0.0-preview
```

That command also creates an unsigned DMG and smoke-launches the installed `/Applications/Baseline.app` copy.

Unsigned DMG release publishing is handled by `.github/workflows/release.yml` when a `vX.Y.Z` tag is pushed.
