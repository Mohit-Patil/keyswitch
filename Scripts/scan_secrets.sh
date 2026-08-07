#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
gitleaks_binary="$("$repository_root/Scripts/fetch_gitleaks.sh")"

common_arguments=(
    --config "$repository_root/.gitleaks.toml"
    --redact=100
    --no-banner
    --no-color
    --verbose
)

"$gitleaks_binary" git \
    "${common_arguments[@]}" \
    --log-opts="--all" \
    "$repository_root"

"$gitleaks_binary" git \
    "${common_arguments[@]}" \
    --pre-commit \
    "$repository_root"

"$gitleaks_binary" git \
    "${common_arguments[@]}" \
    --staged \
    "$repository_root"
