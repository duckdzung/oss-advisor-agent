#!/usr/bin/env bash
# deps.dev adapter. Emits a normalized fragment for one package.
# Usage: fetch_depsdev.sh --ecosystem <e> --name <n> [--version <v>] [--repo <url>] [--raw-file <path>]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"

ECO=""; NAME=""; VER=""; REPO=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  --version) VER="$2"; shift 2;;
  --repo) REPO="$2"; shift 2;;
  --raw-file) RAW_FILE="$2"; shift 2;;
  *) shift;;
esac; done

# Map our ecosystem id to deps.dev system id.
depsdev_system() { case "$1" in
  npm) echo NPM;; pypi) echo PYPI;; maven) echo MAVEN;;
  go) echo GO;; cargo) echo CARGO;; nuget) echo NUGET;; *) echo "";; esac; }

BASE_URL="https://deps.dev/_/s/$(depsdev_system "$ECO")/p/$(printf %s "$NAME" | jq -sRr @uri)"

# transform_depsdev: reads assembled raw JSON on stdin, prints signals object.
transform_depsdev() {
  local url="$1"
  jq --arg url "$url" '
    {} as $s
    | (.version.licenses[0] // null) as $lic
    | (.relatedProjects.dependentCount // null) as $dep
    | (.relatedProjects.scorecard.overallScore // null) as $sc
    | $s
      | (if $lic != null then .["licensing.license"]={value:$lic,citations:[{url:$url}]} else . end)
      | (if $dep != null then .["adoption.dependents"]={value:$dep,citations:[{url:$url}]} else . end)
      | (if $sc  != null then .["security.scorecard"]={value:$sc,citations:[{url:$url}]} else . end)
  '
}

if [ -n "$RAW_FILE" ]; then
  raw="$(cat "$RAW_FILE")"
else
  # Real call assembles version + project; on any failure emit ok:false.
  if ! raw="$(http_get anon "$BASE_URL" 86400)"; then
    emit_fragment depsdev false '{}' '["deps.dev fetch failed"]'; exit 0
  fi
fi

signals="$(printf '%s' "$raw" | transform_depsdev "https://deps.dev/$ECO/$NAME" 2>/dev/null)" || { emit_fragment depsdev false '{}' '["malformed response"]'; exit 0; }
emit_fragment depsdev true "$signals" '[]'
