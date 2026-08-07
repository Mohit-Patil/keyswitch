#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/generate_update_appcast.sh <update-zip> <version>

Validates a notarized KeySwitch update ZIP, signs it with the Sparkle EdDSA key
stored under the com.mohitpatil.keyswitch Keychain account, and updates the
signed docs/appcast.xml feed. Upload the ZIP to the matching GitHub Release
before publishing the updated feed.
EOF
}

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 64
fi

archive_path="$1"
version="$2"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
feed_path="$repository_root/docs/appcast.xml"
archive_name="$(basename "$archive_path")"
expected_archive_name="KeySwitch-v${version}-macOS-universal.zip"
download_url_prefix="https://github.com/Mohit-Patil/keyswitch/releases/download/v${version}/"
download_url="${download_url_prefix}${archive_name}"

if [[ ! -f "$archive_path" ]]; then
    echo "error: update archive not found: $archive_path" >&2
    exit 66
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
    echo "error: version must look like 1.2.3" >&2
    exit 64
fi

if [[ "$archive_name" != "$expected_archive_name" ]]; then
    echo "error: expected archive name $expected_archive_name" >&2
    exit 65
fi

if [[ ! -f "$feed_path" ]]; then
    echo "error: missing update feed: $feed_path" >&2
    exit 66
fi

sparkle_tools="$("$repository_root/Scripts/fetch_sparkle_tools.sh")"
generate_appcast="$sparkle_tools/bin/generate_appcast"
generate_keys="$sparkle_tools/bin/generate_keys"
sign_update="$sparkle_tools/bin/sign_update"
temporary_directory="$(mktemp -d /tmp/keyswitch-appcast.XXXXXX)"
extracted_directory="$temporary_directory/extracted"
archives_directory="$temporary_directory/archives"

cleanup() {
    case "$temporary_directory" in
        /tmp/keyswitch-appcast.*)
            find "$temporary_directory" -depth -delete 2>/dev/null || true
            ;;
    esac
}
trap cleanup EXIT

mkdir -p "$extracted_directory" "$archives_directory"
ditto -x -k "$archive_path" "$extracted_directory"

app_path="$extracted_directory/KeySwitch.app"
if [[ ! -d "$app_path" ]]; then
    echo "error: update archive must contain KeySwitch.app at its root" >&2
    exit 65
fi

actual_version="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$app_path/Contents/Info.plist")"
if [[ "$actual_version" != "$version" ]]; then
    echo "error: archived app version is $actual_version, not $version" >&2
    exit 65
fi

actual_build="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleVersion' \
    "$app_path/Contents/Info.plist")"
if [[ ! "$actual_build" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: archived app build must be a positive integer" >&2
    exit 65
fi

latest_feed_build="$(
    sed -n 's/.*<sparkle:version>\([^<]*\)<\/sparkle:version>.*/\1/p' "$feed_path" |
        sort -n |
        tail -1
)"
if [[ -n "$latest_feed_build" ]]; then
    if [[ ! "$latest_feed_build" =~ ^[1-9][0-9]*$ ]]; then
        echo "error: existing appcast contains a nonnumeric build version" >&2
        exit 65
    fi
    if (( actual_build <= latest_feed_build )); then
        echo "error: build $actual_build must be newer than appcast build $latest_feed_build" >&2
        exit 65
    fi
fi

if grep -Fq "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" "$feed_path"; then
    echo "error: version $version is already present in the appcast" >&2
    exit 65
fi

embedded_public_key="$(/usr/libexec/PlistBuddy \
    -c 'Print :SUPublicEDKey' \
    "$app_path/Contents/Info.plist")"
keychain_public_key="$("$generate_keys" \
    --account com.mohitpatil.keyswitch -p)"
if [[ "$embedded_public_key" != "$keychain_public_key" ]]; then
    echo "error: archived app Sparkle key does not match the release Keychain" >&2
    exit 65
fi

"$sign_update" \
    --account com.mohitpatil.keyswitch \
    --verify \
    "$feed_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
lipo "$app_path/Contents/MacOS/KeySwitch" -verify_arch arm64 x86_64

if ! curl --location --fail --silent --show-error --head "$download_url" >/dev/null; then
    echo "error: upload and publish the update archive before updating the feed" >&2
    echo "missing enclosure: $download_url" >&2
    exit 69
fi

ditto "$archive_path" "$archives_directory/$archive_name"
ditto "$feed_path" "$archives_directory/appcast.xml"
release_notes_path="$archives_directory/${archive_name%.zip}.html"
"$repository_root/Scripts/changelog_to_html.py" \
    "$repository_root/CHANGELOG.md" \
    "$version" \
    "$release_notes_path"

"$generate_appcast" \
    --account com.mohitpatil.keyswitch \
    --download-url-prefix "$download_url_prefix" \
    --embed-release-notes \
    --full-release-notes-url "https://github.com/Mohit-Patil/keyswitch/releases/tag/v${version}" \
    --link "https://mohit-patil.github.io/keyswitch/" \
    --maximum-versions 10 \
    --maximum-deltas 0 \
    "$archives_directory"

"$sign_update" \
    --account com.mohitpatil.keyswitch \
    --disable-signing-warning \
    "$archives_directory/appcast.xml"
"$sign_update" \
    --account com.mohitpatil.keyswitch \
    --verify \
    "$archives_directory/appcast.xml"

xmllint --noout "$archives_directory/appcast.xml"
grep -Fq "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" \
    "$archives_directory/appcast.xml"
grep -Fq "url=\"${download_url}\"" "$archives_directory/appcast.xml"
grep -Fq "sparkle:edSignature=" "$archives_directory/appcast.xml"
grep -Fq "<!-- sparkle-signatures:" "$archives_directory/appcast.xml"

ditto "$archives_directory/appcast.xml" "$feed_path"

echo "Updated signed feed: $feed_path"
echo "Update enclosure: $download_url"
