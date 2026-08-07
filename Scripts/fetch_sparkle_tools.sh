#!/bin/bash

set -euo pipefail

sparkle_version="2.9.5"
sparkle_archive="Sparkle-${sparkle_version}.tar.xz"
sparkle_url="https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/${sparkle_archive}"
sparkle_sha256="015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tools_root="$repository_root/.build/sparkle-tools/${sparkle_version}"

if [[ -x "$tools_root/bin/generate_appcast" && -x "$tools_root/bin/sign_update" ]]; then
    printf '%s\n' "$(cd "$tools_root" && pwd -P)"
    exit 0
fi

mkdir -p "$repository_root/.build/sparkle-tools"
temporary_directory="$(mktemp -d /tmp/keyswitch-sparkle-tools.XXXXXX)"

cleanup() {
    case "$temporary_directory" in
        /tmp/keyswitch-sparkle-tools.*)
            find "$temporary_directory" -depth -delete 2>/dev/null || true
            ;;
    esac
}
trap cleanup EXIT

curl --location --fail --silent --show-error \
    --output "$temporary_directory/$sparkle_archive" \
    "$sparkle_url"

actual_sha256="$(shasum -a 256 "$temporary_directory/$sparkle_archive" | awk '{ print $1 }')"
if [[ "$actual_sha256" != "$sparkle_sha256" ]]; then
    echo "error: Sparkle tools checksum mismatch" >&2
    exit 65
fi

mkdir -p "$tools_root"
tar -xf "$temporary_directory/$sparkle_archive" -C "$tools_root"

test -x "$tools_root/bin/generate_appcast"
test -x "$tools_root/bin/sign_update"
test -x "$tools_root/bin/generate_keys"

printf '%s\n' "$(cd "$tools_root" && pwd -P)"
