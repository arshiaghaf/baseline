# Contributing to Baseline

Thanks for helping improve Baseline. This project is a macOS menubar app built with SwiftUI and Tuist.

## Development Setup

Requirements:
- macOS 26 or newer
- Xcode with Swift 6 support
- Tuist

Install Tuist:

```bash
brew install tuist
```

Generate the project:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate
```

Open `Baseline.xcworkspace` in Xcode and run the `Baseline` scheme.

## Branches And Pull Requests

- Create focused branches for each change.
- Keep pull requests small enough to review.
- Include tests for behavior changes.
- Update docs when user-facing behavior, setup, or release steps change.
- Do not commit generated Xcode/Tuist artifacts.

## Architecture Guidelines

Baseline is intentionally layered:

- Models define stable domain contracts.
- Clients perform source-specific IO and mapping.
- Store code coordinates refresh lifecycle, policy, persistence, and actions.
- SwiftUI views render state and dispatch intents only.

Avoid adding networking, filesystem scanning, subprocess execution, or business-policy decisions directly inside SwiftUI view bodies.

## Validation

Run these before opening a pull request:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild -project Baseline.xcodeproj -scheme Baseline -configuration Debug -destination 'platform=macOS' -derivedDataPath .DerivedData build
xcodebuild -project Baseline.xcodeproj -scheme Baseline -destination 'platform=macOS' -derivedDataPath .DerivedData test
```

If a command cannot run in your environment, mention that in the PR and include the failure output.

## Security-Sensitive Changes

Be careful with code that:
- Runs `brew`, `mas`, or other local executables.
- Parses remote update metadata.
- Opens external URLs.
- Writes persisted app state.

Prefer typed inputs, allowlisted executable resolution, and conservative fallback behavior.
