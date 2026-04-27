# Continuous Integration

This repository intentionally does not include a GitHub Actions workflow yet.

Baseline currently targets macOS 26. CI should be added once the public macOS runner image and Xcode version can reliably build and test that deployment target.

Until then, validate changes locally:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild -project Baseline.xcodeproj -scheme Baseline -configuration Debug -destination 'platform=macOS' -derivedDataPath .DerivedData build
xcodebuild -project Baseline.xcodeproj -scheme Baseline -destination 'platform=macOS' -derivedDataPath .DerivedData test
```

When CI is added, it should:
- Install or bootstrap Tuist.
- Generate the Xcode project.
- Build `Baseline`.
- Run unit tests on `platform=macOS`.
- Avoid committing generated project files.
