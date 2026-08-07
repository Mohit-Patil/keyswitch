# Changelog

All notable changes to KeySwitch will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/) once releases
are tagged. Until version 1.0, minor releases may contain breaking changes.

## [Unreleased]

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
