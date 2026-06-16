#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
frags="$(mktemp)"
cat > "$frags" <<'JSON'
[
  {"source":"depsdev","ok":true,"signals":{"licensing.license":{"value":"Apache-2.0","citations":[{"url":"d"}]},"adoption.dependents":{"value":10,"citations":[]}},"notes":[]},
  {"source":"registry","ok":true,"signals":{"licensing.license":{"value":"MIT","citations":[{"url":"r"}]},"adoption.downloads_recent":{"value":99,"citations":[]}},"notes":[]},
  {"source":"snyk","ok":false,"signals":{},"notes":["skipped: no snyk API key configured"]}
]
JSON
out="$(bash "$HERE/../collect.sh" --ecosystem maven --name com.zaxxer:HikariCP --version 5.1.0 --fragments-file "$frags")"
# precedence: depsdev wins license over registry
[ "$(echo "$out" | jq -r '.signals["licensing.license"].value')" = "Apache-2.0" ] || { echo "precedence"; exit 1; }
[ "$(echo "$out" | jq -r '.signals["licensing.license"].source')" = "depsdev" ] || { echo "source-stamp"; exit 1; }
[ "$(echo "$out" | jq -r '.signals["adoption.downloads_recent"].value')" = "99" ] || { echo "merge-union"; exit 1; }
# sources_used excludes failed snyk; sources_degraded includes it
echo "$out" | jq -e '.sources_used | index("depsdev")' >/dev/null || { echo "used"; exit 1; }
echo "$out" | jq -e '.sources_degraded | index("snyk")' >/dev/null || { echo "degraded"; exit 1; }
rm -f "$frags"
echo "test_collect_merge ok"
