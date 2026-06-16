#!/usr/bin/env bash
# Registry adapter: npm | pypi | maven. Assembles a common shape then transforms.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"

ECO=""; NAME=""; VER=""; RAW_FILE=""; ASSEMBLE_RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version) VER="$2"; shift 2;; --repo) shift 2;;
  --raw-file) RAW_FILE="$2"; shift 2;;
  # Test seam: feed a raw maven Solr response and run it through maven assembly offline.
  --assemble-raw-file) ASSEMBLE_RAW_FILE="$2"; shift 2;;
  *) shift;; esac; done

# transform_registry: assembled shape -> signals
transform_registry() {
  local url="$1"
  jq --arg url "$url" '
    . as $in
    | {}
    | (if $in.license != null then .["licensing.license"]={value:$in.license,citations:[{url:$url}]} else . end)
    | (if $in.downloads_recent != null then .["adoption.downloads_recent"]={value:$in.downloads_recent,citations:[{url:$url}]} else . end)
    | (if $in.latest != null then
         .["stability.semver_compliant"]={value:(($in.latest|test("^[0-9]+\\.[0-9]+\\.[0-9]+"))),citations:[{url:$url}]}
       else . end)
  '
}

assemble_npm() {
  local meta dl
  meta="$(http_get anon "https://registry.npmjs.org/$(printf %s "$NAME" | jq -sRr @uri)" 86400)" || return 1
  dl="$(http_get anon "https://api.npmjs.org/downloads/point/last-month/$(printf %s "$NAME" | jq -sRr @uri)" 86400)" || dl='{}'
  jq -n --argjson meta "$meta" --argjson dl "$dl" '
    { license: ($meta.license // null),
      downloads_recent: ($dl.downloads // null),
      latest: ($meta["dist-tags"].latest // null),
      versions_count: (($meta.versions // {}) | length) }'
}

assemble_pypi() {
  local meta
  meta="$(http_get anon "https://pypi.org/pypi/$(printf %s "$NAME" | jq -sRr @uri)/json" 86400)" || return 1
  jq -n --argjson meta "$meta" '
    { license: ($meta.info.license // null),
      downloads_recent: null,
      latest: ($meta.info.version // null),
      versions_count: (($meta.releases // {}) | length) }'
}

# maven_assemble_jq: reads a raw maven Solr response on stdin -> common assembled shape.
maven_assemble_jq() {
  jq '(.response.docs[0] // {}) as $d
    | { license:null, downloads_recent:null,
        latest:($d.latestVersion // null),
        versions_count:($d.versionCount // null) }'
}

assemble_maven() {
  local g a meta
  g="${NAME%%:*}"; a="${NAME##*:}"
  meta="$(http_get anon "https://search.maven.org/solrsearch/select?q=g:%22$g%22+AND+a:%22$a%22&rows=1&wt=json" 86400)" || return 1
  printf '%s' "$meta" | maven_assemble_jq
}

if [ -n "$ASSEMBLE_RAW_FILE" ]; then
  # Offline path: run a raw maven Solr response through maven assembly, then transform.
  raw="$(maven_assemble_jq < "$ASSEMBLE_RAW_FILE" 2>/dev/null)" || { emit_fragment registry false '{}' '["malformed response"]'; exit 0; }
elif [ -n "$RAW_FILE" ]; then
  raw="$(cat "$RAW_FILE")"
else
  case "$ECO" in
    npm)   raw="$(assemble_npm)"   || { emit_fragment registry false '{}' '["npm fetch failed"]'; exit 0; } ;;
    pypi)  raw="$(assemble_pypi)"  || { emit_fragment registry false '{}' '["pypi fetch failed"]'; exit 0; } ;;
    maven) raw="$(assemble_maven)" || { emit_fragment registry false '{}' '["maven fetch failed"]'; exit 0; } ;;
    *)     emit_fragment registry false '{}' "[\"unsupported ecosystem: $ECO\"]"; exit 0 ;;
  esac
fi

signals="$(printf '%s' "$raw" | transform_registry "registry:$ECO/$NAME" 2>/dev/null)" || { emit_fragment registry false '{}' '["malformed response"]'; exit 0; }
emit_fragment registry true "$signals" '[]'
