# Changelog

All notable changes to KeySwitch will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/) once releases
are tagged. Until version 1.0, minor releases may contain breaking changes.

## [Unreleased]

### Added

- An automated GitHub Actions release pipeline that signs, notarizes, staples,
  packages, publishes, and adds each release to the signed Sparkle feed after
  a new version reaches `main` or a matching version tag is pushed.
- A CI-gated update-feed pull request so the release bot never needs to bypass
  the protected `main` branch.
- Administrator-enforced pull-request protection for `main`, with strict CI,
  resolved-conversation, linear-history, force-push, and deletion safeguards.

## [0.2.1] - 2026-08-07

### Changed

- Complete the first signed Sparkle delivery from the 0.2.0 bootstrap build
  and document the repeatable Xcode cloud-signing and notarization workflow.

## [0.2.0] - 2026-08-07

### Added

- Signed, automatic application updates powered by Sparkle 2. The menu shows
  **Restart to Update** only after Sparkle has prepared a downloaded update.
- An Updates section with automatic-check/download controls, installed-version
  information, and a manual update check.
- A signed GitHub Pages appcast, reproducible Sparkle-tool download, and
  release-feed generation checks.

### Security

- Restrict in-app updates to Developer ID-signed release builds, verify update
  archives before extraction, and require a signed feed and EdDSA-signed
  release archive.

### Fixed

- Point the website download buttons at the current notarized 0.1.1 DMG.

## [0.1.1] - 2026-08-07

### Fixed

- Ship the macOS download as a verified drag-to-Applications disk image, with
  the ZIP retained as an alternative installation format.
- Render every menu-bar agent status as a consistent circular LED and keep
  bright colors inside their individual slots at every indicator size.

## [0.1.0] - 2026-08-07

### Added

- Initial open-source project structure and community documentation.
- Configurable keyboard layer, frosted HUD, Codex Micro slot synchronization,
  agent status lighting, and first-run setup.
- Keyboard-engine, renderer-contract, configuration-migration, and status-HUD
  tests.
- Live six-agent menu-bar indicators with brief state transitions and a
  migration-safe visibility setting and four configurable sizes.
- Compact, Standard, Large, and Extra Large presets for the expanded Codex
  Micro HUD, with migration-safe persistence and live panel resizing.
- Selecting a HUD size or appearance briefly previews the real, nonactivating
  Codex Micro overlay at the screen's top-right; menu-bar sizes update in place.
- Native Launch at Login control with explicit macOS approval and error states.
- A bundled privacy manifest declaring no tracking or collected data and the
  approved reasons for local preferences and double-tap timing.
- A responsive, dependency-free GitHub Pages showcase with interactive HUD
  size and appearance previews.
- The layered-switch KeySwitch identity, optically sized macOS app icons, and
  matching website and favicon marks.

### Changed

- Hardened the local Codex bridge against redirects, remote WebSocket targets,
  malformed endpoints, and oversized discovery responses.
- Reduced repeated renderer and HUD work while preserving live status updates.
- Expanded VoiceOver and Reduce Motion support across the HUD and menu status.
- Unified release version metadata and added universal Release verification to
  CI.

### Removed

- The floating agent-status pill and its timers; passive status now lives in
  the configurable menu-bar indicators.

### Security

- Local release artifacts, profiling traces, signing identities, and private
  design-review captures are excluded from the repository.

[Unreleased]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Mohit-Patil/keyswitch/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/Mohit-Patil/keyswitch/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Mohit-Patil/keyswitch/releases/tag/v0.1.0
