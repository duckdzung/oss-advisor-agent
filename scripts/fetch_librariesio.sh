#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"
CREDS="$HERE/creds.sh"
ECO=""; NAME=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version|--repo) shift 2;; --raw-file) RAW_FILE="$2"; shift 2;; *) shift;; esac; done

if [ -z "$RAW_FILE" ] && ! bash "$CREDS" has librariesio; then
  emit_fragment librariesio false '{}' '["skipped: no librariesio API key configured"]'; exit 0
fi
platform() { case "$1" in npm) echo npm;; pypi) echo pypi;; maven) echo maven;; *) echo "$1";; esac; }
if [ -n "$RAW_FILE" ]; then raw="$(cat "$RAW_FILE")"; else
  url="https://libraries.io/api/$(platform "$ECO")/$(printf %s "$NAME" | jq -sRr @uri)"
  raw="$(http_get librariesio "$url" 86400)" || { emit_fragment librariesio false '{}' '["librariesio fetch failed"]'; exit 0; }
fi
signals="$(printf '%s' "$raw" | jq '
  "https://libraries.io" as $url
  | . as $in
  | {}
  | (if $in.dependents_count != null then .["adoption.dependents"]={value:$in.dependents_count,citations:[{url:$url}]} else . end)' 2>/dev/null)" || { emit_fragment librariesio false '{}' '["malformed response"]'; exit 0; }
emit_fragment librariesio true "$signals" '[]'
