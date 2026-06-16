#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OSS_ADVISOR_CREDS_FILE="$(mktemp)"; rm -f "$OSS_ADVISOR_CREDS_FILE"
trap 'rm -f "$OSS_ADVISOR_CREDS_FILE"' EXIT
for a in librariesio snyk socket; do
  frag="$(bash "$HERE/../fetch_$a.sh" --ecosystem npm --name express --version 4.18.2)"
  [ "$(echo "$frag" | jq -r '.ok')" = "false" ] || { echo "$a should be ok:false without key"; exit 1; }
  echo "$frag" | jq -e '.notes | map(test("key"; "i")) | any' >/dev/null || { echo "$a missing no-key note"; exit 1; }
done
echo "test_keyed_adapters_skip ok"
