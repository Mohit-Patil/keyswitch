#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/create_release_dmg.sh <KeySwitch.app> <version> [output-directory]

Creates a compressed macOS disk image containing KeySwitch.app and an
Applications shortcut. The app must already be Developer ID signed and have a
stapled notarization ticket.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 64
fi

app_path="$1"
version="$2"
output_directory="${3:-Release}"

if [[ ! -d "$app_path" || ! -f "$app_path/Contents/Info.plist" ]]; then
    echo "error: app bundle not found: $app_path" >&2
    exit 66
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
    echo "error: version must look like 1.2.3" >&2
    exit 64
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg is required (install it with: brew install create-dmg)" >&2
    exit 69
fi

actual_version="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$app_path/Contents/Info.plist")"
if [[ "$actual_version" != "$version" ]]; then
    echo "error: app version is $actual_version, not requested version $version" >&2
    exit 65
fi

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd -P)"
output_path="$output_directory/KeySwitch-v${version}-macOS-universal.dmg"
checksum_path="$output_path.sha256"

work_directory="$(mktemp -d /tmp/keyswitch-dmg.XXXXXX)"
source_directory="$work_directory/source"
mount_directory="$work_directory/mount"
mounted_device=""

cleanup() {
    if [[ -n "$mounted_device" ]]; then
        hdiutil detach "$mounted_device" -quiet >/dev/null 2>&1 || true
    fi

    case "$work_directory" in
        /tmp/keyswitch-dmg.*)
            find "$work_directory" -depth -delete 2>/dev/null || true
            ;;
    esac
}
trap cleanup EXIT

echo "Verifying notarized app…"
codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
lipo "$app_path/Contents/MacOS/KeySwitch" -verify_arch arm64 x86_64

mkdir -p "$source_directory" "$mount_directory"
ditto "$app_path" "$source_directory/KeySwitch.app"

echo "Creating drag-to-Applications disk image…"
create-dmg \
    --volname "KeySwitch" \
    --volicon "$app_path/Contents/Resources/AppIcon.icns" \
    --window-pos 240 160 \
    --window-size 660 400 \
    --text-size 14 \
    --icon-size 128 \
    --icon "KeySwitch.app" 170 190 \
    --hide-extension "KeySwitch.app" \
    --app-drop-link 490 190 \
    --filesystem HFS+ \
    --format UDZO \
    --no-internet-enable \
    --overwrite \
    "$output_path" \
    "$source_directory"

echo "Verifying disk image contents…"
hdiutil verify "$output_path"
attach_output="$(hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_directory" \
    "$output_path")"
mounted_device="$(printf '%s\n' "$attach_output" | awk '/^\/dev\// { print $1; exit }')"

test -d "$mount_directory/KeySwitch.app"
test -L "$mount_directory/Applications"
test "$(readlink "$mount_directory/Applications")" = "/Applications"
codesign --verify --deep --strict --verbose=2 "$mount_directory/KeySwitch.app"
xcrun stapler validate "$mount_directory/KeySwitch.app"
spctl --assess --type execute --verbose=4 "$mount_directory/KeySwitch.app"
lipo "$mount_directory/KeySwitch.app/Contents/MacOS/KeySwitch" \
    -verify_arch arm64 x86_64

(
    cd "$output_directory"
    shasum -a 256 "$(basename "$output_path")"
) > "$checksum_path"

echo "Created: $output_path"
echo "Checksum: $checksum_path"
