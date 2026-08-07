#!/bin/bash

set -euo pipefail

create_dmg_version="1.3.0"
create_dmg_archive="create-dmg-${create_dmg_version}.tar.gz"
create_dmg_url="https://github.com/create-dmg/create-dmg/archive/refs/tags/v${create_dmg_version}.tar.gz"
create_dmg_sha256="c50d2bc97c3d6292642bac55f530d247eaf4bf65ee605f26b4caf339383e381c"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tools_root="$repository_root/.build/create-dmg/${create_dmg_version}"

if [[ -x "$tools_root/create-dmg" ]]; then
    printf '%s\n' "$tools_root"
    exit 0
fi

mkdir -p "$repository_root/.build/create-dmg"
temporary_directory="$(mktemp -d /tmp/keyswitch-create-dmg.XXXXXX)"

cleanup() {
    case "$temporary_directory" in
        /tmp/keyswitch-create-dmg.*)
            find "$temporary_directory" -depth -delete 2>/dev/null || true
            ;;
    esac
}
trap cleanup EXIT

curl --location --fail --silent --show-error \
    --output "$temporary_directory/$create_dmg_archive" \
    "$create_dmg_url"

actual_sha256="$(
    shasum -a 256 "$temporary_directory/$create_dmg_archive" |
        awk '{ print $1 }'
)"
if [[ "$actual_sha256" != "$create_dmg_sha256" ]]; then
    echo "error: create-dmg checksum mismatch" >&2
    exit 65
fi

mkdir -p "$tools_root"
tar -xzf "$temporary_directory/$create_dmg_archive" \
    --strip-components 1 \
    -C "$tools_root"

test -x "$tools_root/create-dmg"
test "$("$tools_root/create-dmg" --version)" = \
    "create-dmg ${create_dmg_version}"

printf '%s\n' "$tools_root"
