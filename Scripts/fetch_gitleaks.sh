#!/bin/bash

set -euo pipefail

gitleaks_version="8.30.1"

case "$(uname -m)" in
    arm64)
        gitleaks_architecture="arm64"
        gitleaks_sha256="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
        gitleaks_binary_sha256="ba52fb1bfabbcde42f032afad3d6e0b19dff8ed105229a16e7caa338bbc0e84f"
        ;;
    x86_64)
        gitleaks_architecture="x64"
        gitleaks_sha256="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
        gitleaks_binary_sha256="cee01fea7173f1b779dff188e1c26ecbcb4027d394acc573b23aaf0be260e291"
        ;;
    *)
        echo "error: unsupported architecture: $(uname -m)" >&2
        exit 65
        ;;
esac

gitleaks_archive="gitleaks_${gitleaks_version}_darwin_${gitleaks_architecture}.tar.gz"
gitleaks_url="https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_version}/${gitleaks_archive}"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tools_root="$repository_root/.build/gitleaks/${gitleaks_version}/${gitleaks_architecture}"
gitleaks_binary="$tools_root/gitleaks"

if [[ -x "$gitleaks_binary" ]]; then
    test "$(shasum -a 256 "$gitleaks_binary" | awk '{ print $1 }')" = \
        "$gitleaks_binary_sha256"
    test "$("$gitleaks_binary" version)" = "$gitleaks_version"
    printf '%s\n' "$gitleaks_binary"
    exit 0
fi

temporary_directory="$(mktemp -d /tmp/keyswitch-gitleaks.XXXXXX)"

cleanup() {
    case "$temporary_directory" in
        /tmp/keyswitch-gitleaks.*)
            find "$temporary_directory" -depth -delete 2>/dev/null || true
            ;;
    esac
}
trap cleanup EXIT

curl --location --fail --silent --show-error \
    --output "$temporary_directory/$gitleaks_archive" \
    "$gitleaks_url"

actual_sha256="$(
    shasum -a 256 "$temporary_directory/$gitleaks_archive" |
        awk '{ print $1 }'
)"
if [[ "$actual_sha256" != "$gitleaks_sha256" ]]; then
    echo "error: Gitleaks checksum mismatch" >&2
    exit 65
fi

mkdir -p "$tools_root"
tar -xzf "$temporary_directory/$gitleaks_archive" \
    -C "$tools_root" \
    gitleaks

test -x "$gitleaks_binary"
test "$(shasum -a 256 "$gitleaks_binary" | awk '{ print $1 }')" = \
    "$gitleaks_binary_sha256"
test "$("$gitleaks_binary" version)" = "$gitleaks_version"

printf '%s\n' "$gitleaks_binary"
