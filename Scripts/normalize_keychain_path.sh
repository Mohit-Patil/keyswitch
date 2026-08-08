#!/bin/bash

set -euo pipefail

raw_path="$(cat)"
normalized_path="$(
  printf '%s\n' "$raw_path" |
    sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
)"

if [[ -z "$normalized_path" ]]; then
  echo "security returned an empty keychain path." >&2
  exit 1
fi
if [[ "$normalized_path" == *$'\n'* ]]; then
  echo "security returned more than one keychain path." >&2
  exit 1
fi
if [[ "$normalized_path" != /* ]]; then
  echo "security returned a non-absolute keychain path." >&2
  exit 1
fi

printf '%s\n' "$normalized_path"
