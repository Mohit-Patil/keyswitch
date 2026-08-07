# Contributing to KeySwitch

Thanks for helping improve KeySwitch. Contributions of code, tests,
documentation, accessibility fixes, and careful compatibility research are
welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Security vulnerabilities must be reported through the private process in
[SECURITY.md](SECURITY.md), not through a public issue.

## Before you start

For a bug, search existing issues and collect:

- the macOS version;
- the KeySwitch commit or release;
- the Codex desktop version, when relevant;
- the activation mode and affected mapping;
- exact reproduction steps; and
- sanitized logs or screenshots that do not reveal private task content.

For a substantial feature or architectural change, start a Discussion or issue
before investing in an implementation. This keeps work aligned and avoids
duplicated effort.

## Development setup

Requirements:

- macOS 14 or later;
- Xcode 16 or later; and
- XcodeGen when modifying `project.yml` or the source layout.

Clone and validate the project:

```sh
git clone https://github.com/Mohit-Patil/keyswitch.git
cd keyswitch
xcodebuild -project KeySwitch.xcodeproj -scheme KeySwitch \
  -configuration Debug -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO test
swift build
```

Select your own development team in Xcode if you need to run the global event
tap locally. Never commit a developer team ID, certificate, provisioning
profile, or signing credential.

When changing `project.yml`, run:

```sh
xcodegen generate
```

Commit the manifest and generated Xcode project together.

## Making a change

1. Fork the repository and create a focused branch.
2. Keep the change small enough to review and revert safely.
3. Follow the existing Swift and SwiftUI conventions.
4. Add or update tests for keyboard state, migration, event contracts, and
   safety behavior.
5. Update the README, architecture notes, or changelog when behavior changes.
6. Run the complete validation commands before opening a pull request.

Do not commit local app bundles, archives, Instruments traces, derived data,
screenshots containing private Codex content, or design-review artifacts.

## Safety-sensitive areas

Changes to these areas need explicit tests and a clear risk analysis in the
pull request:

- event-tap suppression and modifier handling;
- activation and automatic-exit state machines;
- Accessibility or Input Monitoring behavior;
- Codex renderer evaluation or remote-debugging behavior;
- commands that launch, terminate, or focus another app; and
- persistence or configuration migrations.

The Escape safety exit must remain available. A mapping change must never make
normal typing unavailable after the layer exits.

## Style

- Prefer SwiftUI-native state and small, focused views.
- Keep AppKit usage at explicit macOS integration boundaries.
- Avoid force unwraps in event, permission, bridge, and persistence paths.
- Use semantic names and comments that explain why, not what.
- Preserve accessibility labels for interactive controls.
- Keep user-facing text concise and translatable.

There is no required third-party formatter. Match the surrounding code and
allow Xcode to apply standard Swift indentation.

## Pull requests

A good pull request includes:

- a concise problem statement and solution;
- user-visible impact;
- tests run and their results;
- screenshots for visual changes;
- performance or memory evidence for continuous UI work; and
- compatibility and rollback notes for bridge changes.

Pull requests should keep unrelated refactors separate. Maintainers may ask for
changes, additional tests, or a smaller scope before merging.

Unless stated otherwise, contributions are licensed under the repository's
[MIT License](LICENSE).
