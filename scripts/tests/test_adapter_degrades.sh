#!/usr/bin/env bash
# Guards Fix 1: a non-JSON / malformed response must degrade to a valid ok:false
# fragment on stdout (never crash, never non-JSON on stdout), and exit 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/.."

# A body that is decidedly not JSON (e.g. an HTML 404/500 page returned by curl exit 0).
garbage="$(mktemp)"; trap 'rm -f "$garbage"' EXIT
printf 'not json {{{' > "$garbage"

assert_degrades() {
  local adp="$1"; shift
  local out rc
  set +e
  out="$(bash "$SCRIPTS/$adp" "$@" --raw-file "$garbage" 2>/dev/null)"; rc=$?
  set -e
  [ "$rc" -eq 0 ] || { echo "$adp: expected exit 0, got $rc"; exit 1; }
  # stdout must be VALID JSON
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || { echo "$adp: stdout is not valid JSON"; exit 1; }
  [ "$(printf '%s' "$out" | jq -r '.ok')" = "false" ] || { echo "$adp: expected ok:false"; exit 1; }
  [ "$(printf '%s' "$out" | jq -r '.notes | length')" -ge 1 ] || { echo "$adp: expected a note"; exit 1; }
}

assert_degrades fetch_osv.sh      --ecosystem npm --name foo --version 1.0.0
assert_degrades fetch_depsdev.sh  --ecosystem npm --name foo --version 1.0.0
assert_degrades fetch_registry.sh --ecosystem npm --name foo --version 1.0.0
assert_degrades fetch_github.sh   --repo https://github.com/foo/bar

echo "test_adapter_degrades ok"
