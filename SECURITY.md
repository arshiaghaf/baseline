# Security Policy

## Supported Versions

Baseline is pre-1.0 software. Security fixes are handled on the default branch and released as soon as practical.

## Reporting A Vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub private vulnerability reporting if it is enabled for this repository. If it is not enabled yet, open a minimal issue asking for a private reporting channel without including exploit details.

Include:
- Affected version or commit.
- Steps to reproduce.
- Expected and actual behavior.
- Impact and any known workaround.

## Security Notes

Baseline uses public update pathways and local helper tools:
- App Store lookup API.
- Sparkle/DevMate appcast metadata.
- Homebrew metadata and local `brew` commands.
- Optional local `mas` command for App Store update actions.

The project should not require secrets, API keys, private Apple frameworks, or a backend service.

When contributing security-sensitive code, avoid shell string construction for executable actions. Prefer argument arrays, executable validation, and existing security helpers.
