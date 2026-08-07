# Releasing KeySwitch

This checklist is for maintainers. Release credentials and artifacts must not
be committed to the repository.

## Prepare

1. Confirm `main` is green and the worktree is clean.
2. Review open security advisories and release-blocking issues.
3. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   This file is the version source of truth; do not put literal versions in
   `KeySwitchApp/Info.plist`.
4. Run `xcodegen generate` and commit `project.yml`, the generated project,
   and the generated `Info.plist` changes together.
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
plutil -lint \
  .build/release/Build/Products/Release/KeySwitch.app/Contents/Resources/PrivacyInfo.xcprivacy
```

Confirm that the built bundle expanded the versions from `project.yml`:

```sh
app=.build/release/Build/Products/Release/KeySwitch.app
expected_marketing_version="$(
  xcodebuild -project KeySwitch.xcodeproj -target KeySwitch \
    -configuration Release -showBuildSettings |
    awk -F ' = ' \
      '/^[[:space:]]*MARKETING_VERSION = / && !found { print $2; found=1 }'
)"
expected_build_version="$(
  xcodebuild -project KeySwitch.xcodeproj -target KeySwitch \
    -configuration Release -showBuildSettings |
    awk -F ' = ' \
      '/^[[:space:]]*CURRENT_PROJECT_VERSION = / && !found { print $2; found=1 }'
)"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$app/Contents/Info.plist")" = "$expected_marketing_version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$app/Contents/Info.plist")" = "$expected_build_version"
lipo "$app/Contents/MacOS/KeySwitch" -verify_arch arm64 x86_64
```

Public distribution should use the maintainer's Developer ID signing and Apple
notarization workflow. Development-signed or ad-hoc builds are not suitable as
official downloads.

### Cloud-managed Developer ID workflow

When the team uses Apple's cloud-managed Developer ID certificate, create the
archive with the development team selected, then distribute it from Xcode's
Organizer:

```sh
xcodebuild -project KeySwitch.xcodeproj -scheme KeySwitch \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath .build/release/KeySwitch.xcarchive \
  DEVELOPMENT_TEAM="<TEAM_ID>" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO archive
```

In Organizer, select the archive, choose **Distribute App → Developer ID →
Upload**, and complete the validation and upload. Xcode can cloud-sign the app
when no local Developer ID private key is available, then it downloads and
staples the notarization ticket after Apple accepts the submission. Export the
notarized archive for the GitHub Release.

The maintainer must have access to the cloud-managed Developer ID certificate
in App Store Connect. Xcode stores the signed-in account credentials in the
macOS Keychain; no credential belongs in the repository.

After exporting a Developer ID-signed app, create the upload archive, notarize
it, staple the ticket, and validate Gatekeeper before publishing:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  KeySwitch.app KeySwitch-notarization.zip
xcrun notarytool submit KeySwitch-notarization.zip \
  --keychain-profile "KeySwitch Notary" --wait
xcrun stapler staple KeySwitch.app
xcrun stapler validate KeySwitch.app
spctl --assess --type execute --verbose=4 KeySwitch.app
ditto -c -k --sequesterRsrc --keepParent KeySwitch.app KeySwitch.zip
shasum -a 256 KeySwitch.zip > KeySwitch.zip.sha256
```

Store notarization credentials in a maintainer keychain profile. Never put the
Apple ID, app-specific password, API key, or signing certificate in this
repository or in a shell script.

## Publish

1. Tag the release as `vMAJOR.MINOR.PATCH`.
2. Push the tag and create a GitHub Release from the matching changelog entry.
3. Attach only notarized, verified artifacts and their SHA-256 checksums.
4. Confirm the download starts, launches, and presents the expected permission
   flow on a clean user account.
5. Re-run a Codex bridge smoke test against the supported desktop version.

Do not add release bundles or archives to git; GitHub Releases is the artifact
distribution channel.
