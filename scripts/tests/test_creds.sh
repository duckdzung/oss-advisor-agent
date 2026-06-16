#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OSS_ADVISOR_CREDS_FILE="$(mktemp)"
rm -f "$OSS_ADVISOR_CREDS_FILE"
trap 'rm -f "$OSS_ADVISOR_CREDS_FILE"' EXIT
CREDS="$HERE/../creds.sh"

# unknown provider -> has returns 1
if bash "$CREDS" has github; then echo "should not have github yet"; exit 1; fi
# set then has -> 0
bash "$CREDS" set github "ghp_SECRETVALUE123"
bash "$CREDS" has github || { echo "should have github"; exit 1; }
# list must NOT print the secret value
out="$(bash "$CREDS" list)"
echo "$out" | grep -q "github" || { echo "list should mention github"; exit 1; }
if echo "$out" | grep -q "ghp_SECRETVALUE123"; then echo "LEAKED SECRET"; exit 1; fi
# header prints an Authorization header (only used internally by http.sh)
hdr="$(bash "$CREDS" header github)"
echo "$hdr" | grep -q "Authorization: Bearer ghp_SECRETVALUE123" || { echo "bad header"; exit 1; }
echo "test_creds ok"
