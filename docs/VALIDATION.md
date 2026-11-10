# Validation

Use this checklist before preparing a release or validating risky app behavior changes.

## Manual Smoke Matrix

Validate at least one item in each category when possible:

- App Store app with an available update.
- Sparkle or DevMate app with a valid appcast.
- Homebrew cask app with an available update.
- Homebrew formula with an available update.
- Current app with no update.
- Ignored app and ignored Homebrew item.
- Unsupported app with only an external fallback.
- App with malformed or missing update metadata.
- Missing `mas` fallback path.
- Missing Homebrew fallback path.

## Release Artifact Check

```bash
scripts/prepare-unsigned-release.sh <version>
```

Confirm:

- The app executable, Electron Framework, and native admin helper contain only arm64 slices (`lipo -archs`).
- Release notes state that Apple Silicon and macOS 15 or later are required.

- `dist/Baseline-<version>-unsigned.dmg` exists.
- `dist/Baseline-<version>-unsigned-release-notes.md` contains the Apple Silicon requirement followed by the `Highlights`, `Added`, and/or `Fixed` subsections from the finalized changelog section.
- The DMG opens and `Baseline.app` can be copied to `/Applications`.

After the GitHub Release is created, verify its published assets and notes:

```bash
scripts/check-release-assets.sh v<version>
```

## Installed Preview Helper

Run `scripts/validate-preview.sh [preview-version]` only when an installed preview
is intended. Quit the installed app after its current operations finish before
replacement; the helper refuses to stop an existing user session. It stages the
copy beside the installation and checks bundle identity, signature and signing
hash before removing the stopped old bundle. No old-app rollback copy is kept.
A successful installed preview stays running for inspection.

Copy and staging verification failures leave the installed bundle intact.
Promotion failure or interruption after removal can leave the installation absent;
the verified new staging bundle and launch logs remain for diagnosis and retry.
An installed launch failure leaves the new bundle installed. The helper does not
reset user data, settings, history or Keychain state. Mounted and installed smoke
launches use the ordinary profile and can persist migrations.

Only the exact process launched by the helper receives a graceful stop signal.
If shutdown cannot be confirmed, the mount and installation lock remain for
inspection. If a crash leaves `.Baseline-preview-lock` in the installation
directory, confirm no helper or owned preview is running before removing that
empty lock directory and retrying.
