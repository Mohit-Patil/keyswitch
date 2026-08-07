# Releasing KeySwitch

This checklist is for maintainers. Release credentials and artifacts must not
be committed to the repository.

## Prepare

1. Confirm `main` is green and the worktree is clean.
2. Review open security advisories and release-blocking issues.
3. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   This file is the version source of truth; do not put literal versions in
   `KeySwitchApp/Info.plist`. `CURRENT_PROJECT_VERSION` must be greater than
   every build already published in `docs/appcast.xml`.
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

The upload can also be performed noninteractively. Archive with any valid local
Apple Development identity, then create an ignored export-options plist with
these values:

```xml
<key>destination</key>
<string>upload</string>
<key>method</key>
<string>developer-id</string>
<key>signingStyle</key>
<string>automatic</string>
<key>teamID</key>
<string>DEVELOPER_ID_TEAM_ID</string>
```

Submit the archive using the Xcode account stored in Keychain:

```sh
xcodebuild -exportArchive \
  -archivePath .build/release/KeySwitch.xcarchive \
  -exportPath .build/release/upload \
  -exportOptionsPlist .build/release/DeveloperIDExport.plist \
  -allowProvisioningUpdates
```

After Apple accepts the submission, export the cloud-signed app and its stapled
notarization ticket:

```sh
xcodebuild -exportNotarizedApp \
  -archivePath .build/release/KeySwitch.xcarchive \
  -exportPath .build/release/notarized
```

An App Store Connect API key can replace the stored Xcode account only when its
role has Cloud Managed Developer ID signing permission.

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
```

Package the already notarized app in the drag-to-Applications disk image:

```sh
brew install create-dmg
Scripts/create_release_dmg.sh KeySwitch.app 1.2.3 Release
```

The script refuses an app without a valid signature, stapled notarization
ticket, Gatekeeper acceptance, and both `arm64` and `x86_64` slices. It then
mounts the finished image and repeats those checks against the copy inside.
For managed or command-line installs, a ZIP may be published as a secondary
artifact:

```sh
ditto -c -k --sequesterRsrc --keepParent KeySwitch.app \
  KeySwitch-v1.2.3-macOS-universal.zip
shasum -a 256 KeySwitch-v1.2.3-macOS-universal.zip \
  > KeySwitch-v1.2.3-macOS-universal.zip.sha256
```

Store notarization credentials in a maintainer keychain profile. Never put the
Apple ID, app-specific password, API key, or signing certificate in this
repository or in a shell script.

## Sparkle update signing

KeySwitch uses Sparkle 2.9.5. `Scripts/fetch_sparkle_tools.sh` downloads the
matching official tools archive and verifies its pinned SHA-256 digest.

The update signing key is stored in the login Keychain under the
`com.mohitpatil.keyswitch` account. The corresponding public key is committed
as `SUPublicEDKey`; never commit or paste the private key into a terminal log,
issue, pull request, or GitHub Actions secret without a separate security
review.

To inspect the existing public key:

```sh
sparkle_tools="$(Scripts/fetch_sparkle_tools.sh)"
"$sparkle_tools/bin/generate_keys" \
  --account com.mohitpatil.keyswitch -p
```

The first updater-enabled release requires one normal drag-to-Applications
installation. Releases installed after that can update in place.

## Publish

1. Tag the release as `vMAJOR.MINOR.PATCH`.
2. Push the tag and create a GitHub Release from the matching changelog entry.
3. Attach the verified DMG, ZIP, and their SHA-256 checksums. The ZIP is the
   Sparkle update enclosure and is therefore required.
4. Confirm the public ZIP URL resolves, then generate and verify the signed
   update feed:

   ```sh
   Scripts/generate_update_appcast.sh \
     Release/KeySwitch-v1.2.3-macOS-universal.zip 1.2.3
   git diff --check
   xmllint --noout docs/appcast.xml
   ```

   Commit and push `docs/appcast.xml`, wait for GitHub Pages to deploy, and
   confirm `https://mohit-patil.github.io/keyswitch/appcast.xml` contains the
   new version, embedded release notes from `CHANGELOG.md`, and a reachable
   enclosure URL. Do not publish a feed entry that points at a missing release
   asset.
5. Mount the public DMG, confirm it contains `KeySwitch.app` and an Applications
   shortcut, then launch the installed copy and verify the first-run flow on a
   clean user account.
6. Re-run a Codex bridge smoke test against the supported desktop version.
7. From the immediately preceding updater-enabled public build, run **Check for
   Updates**, let the archive download, verify **Restart to Update** appears in
   the menu, and confirm its first click installs and relaunches the new build.

Do not add release bundles or archives to git; GitHub Releases is the artifact
distribution channel.
