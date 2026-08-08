#!/bin/bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <artifact> <api-key-path> <key-id> <issuer-id>" >&2
  exit 64
fi

artifact_path="$1"
api_key_path="$2"
key_id="$3"
issuer_id="$4"
xcrun_bin="${XCRUN_BIN:-xcrun}"
temporary_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
submission_result="$(mktemp "$temporary_root/keyswitch-notary-submit.XXXXXX")"
notarization_log="$(mktemp "$temporary_root/keyswitch-notary-log.XXXXXX")"

cleanup() {
  /bin/unlink "$submission_result" 2>/dev/null || true
  /bin/unlink "$notarization_log" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ! -f "$artifact_path" ]]; then
  echo "Notarization artifact does not exist: $artifact_path" >&2
  exit 66
fi
if [[ ! -f "$api_key_path" ]]; then
  echo "App Store Connect API key does not exist: $api_key_path" >&2
  exit 66
fi

if ! "$xcrun_bin" notarytool submit "$artifact_path" \
  --key "$api_key_path" \
  --key-id "$key_id" \
  --issuer "$issuer_id" \
  --wait \
  --output-format json > "$submission_result"; then
  echo "notarytool failed before returning a completed submission." >&2
  cat "$submission_result" >&2
  exit 1
fi

if ! submission_metadata="$({
  python3 - "$submission_result" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)

print(result.get("id", ""), result.get("status", ""), sep="|")
PY
})"; then
  echo "notarytool returned malformed JSON:" >&2
  cat "$submission_result" >&2
  exit 1
fi
IFS='|' read -r submission_id status <<< "$submission_metadata"

if [[ -z "$submission_id" || -z "$status" ]]; then
  echo "notarytool returned an incomplete result:" >&2
  cat "$submission_result" >&2
  exit 1
fi

echo "Apple notarization submission $submission_id finished with status: $status"
if [[ "$status" == "Accepted" ]]; then
  exit 0
fi

echo "Apple rejected the artifact. Fetching the validation issues..." >&2
if "$xcrun_bin" notarytool log "$submission_id" "$notarization_log" \
  --key "$api_key_path" \
  --key-id "$key_id" \
  --issuer "$issuer_id"; then
  python3 - "$notarization_log" <<'PY' >&2
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)

summary = result.get("statusSummary") or "No status summary was provided."
print(f"Notarization summary: {summary}")
issues = result.get("issues") or []
if not issues:
    print("Apple returned no structured validation issues.")
for issue in issues:
    severity = issue.get("severity", "error").upper()
    message = issue.get("message", "Unknown validation error")
    path = issue.get("path")
    architecture = issue.get("architecture")
    context = ", ".join(value for value in (path, architecture) if value)
    suffix = f" ({context})" if context else ""
    print(f"{severity}: {message}{suffix}")
PY
else
  echo "The notarization issue log could not be retrieved." >&2
fi

exit 1
