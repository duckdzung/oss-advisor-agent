#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"
CREDS="$HERE/creds.sh"
ECO=""; NAME=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version|--repo) shift 2;; --raw-file) RAW_FILE="$2"; shift 2;; *) shift;; esac; done
if [ -z "$RAW_FILE" ] && ! bash "$CREDS" has snyk; then
  emit_fragment snyk false '{}' '["skipped: no snyk API key configured"]'; exit 0
fi
if [ -n "$RAW_FILE" ]; then raw="$(cat "$RAW_FILE")"; else
  # Snyk health/advisor endpoint (org-scoped); see references/data-sources.md for exact path.
  url="https://api.snyk.io/v1/test/$ECO/$(printf %s "$NAME" | jq -sRr @uri)"
  raw="$(http_get snyk "$url" 21600)" || { emit_fragment snyk false '{}' '["snyk fetch failed"]'; exit 0; }
fi
signals="$(printf '%s' "$raw" | jq '
  "https://snyk.io/advisor" as $url
  | . as $in
  | {}
  | (if $in.health.score != null then .["security.scorecard"]={value:($in.health.score/10),citations:[{url:$url}]} else . end)' 2>/dev/null)" || { emit_fragment snyk false '{}' '["malformed response"]'; exit 0; }
emit_fragment snyk true "$signals" '[]'
