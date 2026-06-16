#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
frags="$(mktemp)"
cat > "$frags" <<'JSON'
[
  {"source":"github","ok":true,"signals":{"health.last_commit_days":{"value":20,"citations":[]},"health.bus_factor":{"value":3,"citations":[]},"health.active_maintainers":{"value":3,"citations":[]},"adoption.stars":{"value":20000,"citations":[]},"adoption.forks":{"value":3000,"citations":[]},"security.has_security_md":{"value":true,"citations":[]}},"notes":[]},
  {"source":"osv","ok":true,"signals":{"security.osv_queried":{"value":true,"citations":[]},"security.open_cves":{"value":0,"citations":[]},"security.max_cvss":{"value":null,"citations":[]}},"notes":[]},
  {"source":"depsdev","ok":true,"signals":{"licensing.license":{"value":"Apache-2.0","citations":[]},"adoption.dependents":{"value":8000,"citations":[]},"security.scorecard":{"value":7.8,"citations":[]}},"notes":[]}
]
JSON
facts="$(bash "$HERE/../collect.sh" --ecosystem maven --name com.zaxxer:HikariCP --version 5.1.0 --fragments-file "$frags")"
result="$(echo "$facts" | python3 "$HERE/../score.py" --facts - --profile balanced)"
[ "$(echo "$result" | jq -r '.verdict')" = "adopt" ] || { echo "verdict=$(echo "$result" | jq -r '.verdict')"; exit 1; }
[ "$(echo "$result" | jq -r '.coordinates.name')" = "com.zaxxer:HikariCP" ] || { echo "coords"; exit 1; }
rm -f "$frags"
echo "test_e2e_offline ok"
