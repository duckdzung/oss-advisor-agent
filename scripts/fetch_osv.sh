#!/usr/bin/env bash
# OSV.dev adapter. Always sets security.osv_queried=true when it gets a response.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"

ECO=""; NAME=""; VER=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version) VER="$2"; shift 2;; --repo) shift 2;;
  --raw-file) RAW_FILE="$2"; shift 2;; *) shift;; esac; done

osv_ecosystem() { case "$1" in
  npm) echo npm;; pypi) echo PyPI;; maven) echo Maven;;
  go) echo Go;; cargo) echo crates.io;; nuget) echo NuGet;; *) echo "";; esac; }

# transform_osv: raw OSV query response -> security signals object
transform_osv() {
  jq --arg url "https://osv.dev/list" '
    (.vulns // []) as $v
    | ($v | length) as $count
    | ([ $v[] | (.database_specific.cvss.score // 0) ] | max // 0) as $maxcvss
    | ([ $v[] | select((.database_specific.cvss.score // 0) >= 9)
              | (any(.affected[]?.ranges[]?.events[]?; has("fixed")) | not) ] | any) as $unpatched_crit
    | {
        "security.osv_queried": {value:true, citations:[{url:$url}]},
        "security.open_cves":   {value:$count, citations:[{url:$url}]},
        "security.max_cvss":    {value: (if $maxcvss==0 then null else $maxcvss end), citations:[{url:$url}]},
        "security.unpatched_critical": {value:($unpatched_crit // false), citations:[{url:$url}]}
      }
  '
}

if [ -n "$RAW_FILE" ]; then
  raw="$(cat "$RAW_FILE")"
else
  payload="$(jq -n --arg e "$(osv_ecosystem "$ECO")" --arg n "$NAME" --arg v "$VER" \
    '{package:{ecosystem:$e, name:$n}} + (if $v=="" then {} else {version:$v} end)')"
  if ! raw="$(curl -sS -X POST -H 'Content-Type: application/json' \
        -d "$payload" 'https://api.osv.dev/v1/query' 2>/dev/null)"; then
    emit_fragment osv false '{}' '["osv unreachable"]'; exit 0
  fi
fi

# A non-JSON body (e.g. HTML 404/500 from curl exit 0) must degrade, not crash under pipefail.
signals="$(printf '%s' "$raw" | transform_osv 2>/dev/null)" || { emit_fragment osv false '{}' '["malformed response"]'; exit 0; }
emit_fragment osv true "$signals" '[]'
