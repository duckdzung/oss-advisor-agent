#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"
CREDS="$HERE/creds.sh"
ECO=""; NAME=""; VER=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version) VER="$2"; shift 2;; --repo) shift 2;; --raw-file) RAW_FILE="$2"; shift 2;; *) shift;; esac; done
if [ -z "$RAW_FILE" ] && ! bash "$CREDS" has socket; then
  emit_fragment socket false '{}' '["skipped: no socket API key configured"]'; exit 0
fi
if [ -n "$RAW_FILE" ]; then raw="$(cat "$RAW_FILE")"; else
  url="https://api.socket.dev/v0/npm/$(printf %s "$NAME" | jq -sRr @uri)/$VER/score"
  raw="$(http_get socket "$url" 21600)" || { emit_fragment socket false '{}' '["socket fetch failed"]'; exit 0; }
fi
# Socket supplyChainRisk score 0..1 (higher = safer) -> invert to our 0..1 risk.
signals="$(printf '%s' "$raw" | jq '
  "https://socket.dev" as $url
  | . as $in
  | {}
  | (if $in.score.supplyChainRisk != null
       then .["compatibility.transitive_conflict_risk"]={value:(1 - $in.score.supplyChainRisk),citations:[{url:$url}]}
       else . end)' 2>/dev/null)" || { emit_fragment socket false '{}' '["malformed response"]'; exit 0; }
emit_fragment socket true "$signals" '[]'
