# Releasing Baseline

Baseline currently supports source builds and optional unsigned preview DMGs.

Unsigned DMGs are not notarized by Apple. macOS Gatekeeper may warn users before opening the app. Do not describe unsigned builds as signed, notarized, or production-grade.

## Release Checklist

1. Choose a version, for example `0.1.0`.
2. Update `CHANGELOG.md`.
3. Run validation:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild -project Baseline.xcodeproj -scheme Baseline -configuration Debug -destination 'platform=macOS' -derivedDataPath .DerivedData build
xcodebuild -project Baseline.xcodeproj -scheme Baseline -destination 'platform=macOS' -derivedDataPath .DerivedData test
```

4. Build the unsigned DMG and release-note checksum text:

```bash
scripts/prepare-unsigned-release.sh 0.1.0
```

5. Upload `dist/Baseline-0.1.0-unsigned.dmg` to GitHub Releases.
6. Use `dist/Baseline-0.1.0-unsigned-release-notes.md` as the release-note starting point.
7. Clearly label the artifact as unsigned.

## Future Signed Release Path

When an Apple Developer account is available, the release process should move to Developer ID signing, notarization, stapling, and a signed DMG.

Do not reuse the unsigned release wording once signed builds are available. Update the README and this document at that time.
