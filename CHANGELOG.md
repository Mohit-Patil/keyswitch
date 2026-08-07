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

### Removed

- The floating agent-status pill and its timers; passive status now lives in
  the configurable menu-bar indicators.

### Security

- Local release artifacts, profiling traces, signing identities, and private
  design-review captures are excluded from the repository.
