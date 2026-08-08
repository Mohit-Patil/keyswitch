#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <app-path> <developer-id-identity> <team-id>" >&2
  exit 64
fi

app_path="$1"
developer_id_identity="$2"
team_id="$3"
codesign_bin="${CODESIGN_BIN:-codesign}"
sparkle_path="$app_path/Contents/Frameworks/Sparkle.framework/Versions/Current"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle does not exist: $app_path" >&2
  exit 66
fi

components=(
  "$sparkle_path/XPCServices/Downloader.xpc"
  "$sparkle_path/XPCServices/Installer.xpc"
  "$sparkle_path/Autoupdate"
  "$sparkle_path/Updater.app"
  "$sparkle_path"
  "$app_path"
)

for component in "${components[@]}"; do
  if [[ ! -e "$component" ]]; then
    echo "Expected release component is missing: $component" >&2
    exit 66
  fi

  "$codesign_bin" \
    --force \
    --options runtime \
    --timestamp \
    --preserve-metadata=identifier,entitlements,requirements \
    --sign "$developer_id_identity" \
    "$component"
done

for component in "${components[@]}"; do
  "$codesign_bin" --verify --strict --verbose=2 "$component"
  signature="$($codesign_bin -dv --verbose=4 "$component" 2>&1)"

  if ! grep -Fq "Authority=$developer_id_identity" <<< "$signature"; then
    echo "Developer ID authority is missing from: $component" >&2
    exit 1
  fi
  if ! grep -Fq "TeamIdentifier=$team_id" <<< "$signature"; then
    echo "Developer team identifier is missing from: $component" >&2
    exit 1
  fi
  if grep -Fq "Signature=adhoc" <<< "$signature"; then
    echo "Ad-hoc signature remains on: $component" >&2
    exit 1
  fi
done

"$codesign_bin" --verify --deep --strict --verbose=2 "$app_path"
