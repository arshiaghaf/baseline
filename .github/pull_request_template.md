## Summary

Describe the change and why it is needed.

## Validation

- [ ] `TUIST_SKIP_UPDATE_CHECK=1 tuist build Baseline --configuration Debug`
- [ ] `TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open`
- [ ] `xcodebuild -project Baseline.xcodeproj -scheme Baseline -destination 'platform=macOS' -derivedDataPath .DerivedData test`

If any validation was not run, explain why.

## Checklist

- [ ] I kept generated Xcode/Tuist artifacts out of the PR.
- [ ] I added or updated tests for behavior changes.
- [ ] I updated docs for user-facing changes.
- [ ] I kept networking and update policy out of SwiftUI view bodies.
