#!/usr/bin/env bash
# Find candidate packages for a stated need.
# Usage: discover.sh --ecosystem <e> --query "<text>" [--candidates '<json array of names>']
#                    [--limit N] [--raw-file <search-response>]
# Output: JSON array of {ecosystem,name,version|null}. LLM-supplied candidates are unioned in.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"

ECO=""; QUERY=""; CANDIDATES="[]"; LIMIT=8; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --query) QUERY="$2"; shift 2;;
  --candidates) CANDIDATES="$2"; shift 2;; --limit) LIMIT="$2"; shift 2;;
  --raw-file) RAW_FILE="$2"; shift 2;; *) shift;; esac; done

search_names() {
  case "$ECO" in
    npm)
      local url="https://registry.npmjs.org/-/v1/search?text=$(printf %s "$QUERY" | jq -sRr @uri)&size=$LIMIT"
      local raw; raw="$(http_get anon "$url" 86400)" || { echo '[]'; return; }
      echo "$raw" | jq '[ .objects[]?.package | {name:.name, version:(.version // null)} ]'
      ;;
    maven)
      local url="https://search.maven.org/solrsearch/select?q=$(printf %s "$QUERY" | jq -sRr @uri)&rows=$LIMIT&wt=json"
      local raw; raw="$(http_get anon "$url" 86400)" || { echo '[]'; return; }
      echo "$raw" | jq '[ .response.docs[]? | {name:(.g + ":" + .a), version:(.latestVersion // null)} ]'
      ;;
    *)
      # pypi and others: no reliable free search API -> rely on LLM candidates only.
      echo '[]' ;;
  esac
}

if [ -n "$RAW_FILE" ]; then
  case "$ECO" in
    npm)   search_json="$(jq '[ .objects[]?.package | {name:.name, version:(.version // null)} ]' "$RAW_FILE")" ;;
    maven) search_json="$(jq '[ .response.docs[]? | {name:(.g + ":" + .a), version:(.latestVersion // null)} ]' "$RAW_FILE")" ;;
    *)     search_json="[]" ;;
  esac
else
  search_json="$(search_names)"
fi

# Union search results with LLM-supplied candidate names; dedupe by name; stamp ecosystem.
jq -n --arg eco "$ECO" --argjson search "$search_json" --argjson cands "$CANDIDATES" '
  ($search + ([ $cands[] | {name:., version:null} ]))
  | group_by(.name) | map(.[0])
  | map({ecosystem:$eco, name:.name, version:.version})'
