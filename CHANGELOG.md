# Changelog

All notable changes to KeySwitch will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/) once releases
are tagged. Until version 1.0, minor releases may contain breaking changes.

## [Unreleased]

## [0.3.2] - 2026-08-10

### Added

- Allow KeySwitch activation shortcuts to use a standard keyboard key by
  itself or together with any supported modifiers, while retaining
  modifier-only shortcuts and the recommended Fn + Control default.

### Fixed

- Capture activation shortcuts at the global event tap so system shortcuts do
  not perform their normal action while being recorded.
- Preserve balanced key-down and key-up suppression across layer deactivation,
  configuration changes, recorder cancellation, and event-tap recovery.
- Keep legacy modifier-only shortcut settings compatible with the expanded
  shortcut model and reject malformed persisted trigger keys safely.

## [0.3.1] - 2026-08-10

### Fixed

- Keep Launch at Login actionable when macOS loses the app's existing service
  registration, allowing the signed app to register itself again instead of
  disabling the setting.
- Require a successful `main` CI run for the exact source commit across
  automatic, tag-triggered, and manually dispatched releases.
- Treat the protected Sparkle feed PR's expected maintainer approval as a
  successful release handoff while preserving failures for unexpected feed
  errors.
- Expose editable Micro key surfaces as buttons to macOS accessibility clients.

## [0.3.0] - 2026-08-09

### Fixed

- Restore unfinished onboarding to the foreground after Accessibility is
  granted, so menu-bar-only users are not stranded in System Settings.
- Limit the permission handoff to the newly granted transition so periodic
  permission checks and completed onboarding never steal focus.

## [0.2.7] - 2026-08-09

### Changed

- Allow any single modifier to activate KeySwitch while keeping Fn + Control
  as the recommended default shortcut.
- Map the six agent slots to 1–6 and the four primary command controls to Q–R
  for clearer slot numbering and a compact command row.
- Use the single Accessibility grant that macOS provides for both listening to
  and suppressing keyboard events, instead of also requesting Input Monitoring.
- Show one compact native drag tile beside the Accessibility list so the exact
  installed KeySwitch bundle can be added, then enabled with its system switch.

### Fixed

- Verify the Codex renderer, live Micro state, and official onboarding response
  before reporting a connection or completing first-run setup.
- Keep KeySwitch in front while Codex restarts for first-run connection, return
  to a clear final setup action, and surface a retry if reconnection times out.
- Cancel pending Codex setup work when onboarding is dismissed so it cannot
  reopen unexpectedly after a delayed connection.
- Suppress the macOS Globe/emoji action when Fn alone is selected as the
  activation shortcut.
- Stop the permission drag guide's tracking timer after a completed drag and
  keep its overlay inside the correct display on multi-monitor Macs.
- Avoid the unnecessary Input Monitoring quit-and-reopen prompt during setup.
- Use a live keyboard event-tap probe so the running app sees Accessibility
  changes even when macOS keeps `AXIsProcessTrusted()` cached and stale.
- Register the running bundle with TCC before opening System Settings, while
  keeping the drag tile as a fallback for stale or missing list entries.
- Reflect Accessibility revocation immediately and stop any event tap that
  briefly survives after the user turns the permission off in System Settings.

## [0.2.6] - 2026-08-09

### Added

- Show a Soren-style floating permission guide containing the real KeySwitch
  app bundle, which users can drag directly into the macOS Input Monitoring or
  Accessibility list.

### Changed

- Guide first-run permission setup through Input Monitoring and Accessibility
  one at a time, automatically hiding the drag guide after an accepted drop or
  completed grant.

### Fixed

- Prevent onboarding permission actions from opening a System Settings list
  with no KeySwitch entry and no way to understand what to do next.

## [0.2.5] - 2026-08-09

### Fixed

- Highlight the full menu-bar action row on pointer hover and press so every
  option has clear, consistent interaction feedback in the custom panel.

## [0.2.4] - 2026-08-09

### Changed

- Keep the KeySwitch Codex Micro settings focused on mapping Mac keys to the
  fixed Micro controls, while Codex remains the source of truth for keycaps,
  actions, agent selection, control behavior, and lighting.
- Use Codex's brightness and inactivity timing directly for the virtual Micro
  lighting, and keep KeySwitch's optional animation preference under General
  settings.

## [0.2.3] - 2026-08-09

### Fixed

- Keep the keyboard layer active for as long as the activation shortcut is
  held in Hold mode, regardless of the configured inactivity timeout.
- Render every active menu-bar agent indicator as a consistent, solid color
  circle, including error states, while inactive slots use a neutral ring.
- Keep the menu-bar legend in Settings synchronized with the rendered
  indicator shapes.
- Sign Sparkle update feeds from an ephemeral key file so headless release
  runners do not stall on a Keychain permission prompt.

### Changed

- Add a feed-only recovery path for an existing release whose public Sparkle
  feed still needs to be published.

## [0.2.2] - 2026-08-08

### Added

- An automated GitHub Actions release pipeline that signs, notarizes, staples,
  packages, publishes, and adds each release to the signed Sparkle feed after
  a new version reaches `main` or a matching version tag is pushed.
- A CI-gated update-feed pull request so the release bot never needs to bypass
  the protected `main` branch.
- Administrator-enforced pull-request protection for `main`, with strict CI,
  resolved-conversation, linear-history, force-push, and deletion safeguards.

### Changed

- Start a `main` release only after the complete CI workflow succeeds, then
  build and publish the exact commit that CI tested.

### Fixed

- Keep selected and unselected menu-bar agent statuses visually consistent by
  rendering every active status as the same filled circular indicator.

### Security

- Scan the complete Git history for credentials during CI, restrict Actions to
  immutable GitHub-owned revisions, and minimize signing-key lifetime on the
  release runner.
- Restrict the privileged post-CI release trigger to successful `push` runs
  from this repository's `main` branch and verify its tested commit before any
  release credentials are used.
- Bind the undocumented local Codex debugging bridge explicitly to loopback.

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

[Unreleased]: https://github.com/Mohit-Patil/keyswitch/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/Mohit-Patil/keyswitch/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Mohit-Patil/keyswitch/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.7...v0.3.0
[0.2.7]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Mohit-Patil/keyswitch/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Mohit-Patil/keyswitch/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/Mohit-Patil/keyswitch/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Mohit-Patil/keyswitch/releases/tag/v0.1.0
