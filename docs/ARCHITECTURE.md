# Architecture

Baseline is a standalone macOS menubar app. It scans installed apps, checks public update sources, and routes users to the safest available update action.

## Layers

Baseline keeps IO and policy out of SwiftUI views:

- `Sources/Models` contains domain contracts, version comparison, support levels, update records, and persistence snapshots.
- `Sources/Clients` contains source-specific scanning, network lookup, parsing, and mapping.
- `Sources/Store` coordinates refresh lifecycle, caching, persistence, precedence, filtering, and update actions.
- `Sources/Views` renders state and sends user intents back to the store.

## Update Sources

Supported sources:

- App Store lookup API.
- Sparkle/DevMate appcast parsing.
- Homebrew cask and formula metadata.

Precedence for app updates is:

```text
App Store > Sparkle/Appcast > Homebrew
```

When a direct update action is unavailable or unsafe, Baseline should show an explicit external-update fallback instead of guessing.

## Safety Boundaries

Baseline should not use private Apple frameworks, bundled secrets, API keys, or a backend service.

Subprocess actions should use argument arrays and validated executable paths. Homebrew token input should pass existing validation before being used in commands.

SwiftUI views should not perform networking, scanning, subprocess execution, or source-precedence decisions.
