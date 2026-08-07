# Releasing KeySwitch

This checklist is for maintainers. Release credentials and artifacts must not
be committed to the repository.

## Prepare

1. Confirm `main` is green and the worktree is clean.
2. Review open security advisories and release-blocking issues.
3. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
4. Run `xcodegen generate` and commit the generated project changes.
5. Move completed items from `Unreleased` to a dated version in
   `CHANGELOG.md`.
6. Run the full test suite with code signing disabled.

## Build

Create a universal Release build:

```sh
xcodebuild -project KeySwitch.xcodeproj -scheme KeySwitch \
  -configuration Release -derivedDataPath .build/release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

Verify both architectures and the signature:

```sh
file .build/release/Build/Products/Release/KeySwitch.app/Contents/MacOS/KeySwitch
codesign --verify --deep --strict --verbose=2 \
  .build/release/Build/Products/Release/KeySwitch.app
```

Public distribution should use the maintainer's Developer ID signing and Apple
notarization workflow. Development-signed or ad-hoc builds are not suitable as
official downloads.

## Publish

1. Tag the release as `vMAJOR.MINOR.PATCH`.
2. Push the tag and create a GitHub Release from the matching changelog entry.
3. Attach only notarized, verified artifacts and their SHA-256 checksums.
4. Confirm the download starts, launches, and presents the expected permission
   flow on a clean user account.
5. Re-run a Codex bridge smoke test against the supported desktop version.

Do not add release bundles or archives to git; GitHub Releases is the artifact
distribution channel.
