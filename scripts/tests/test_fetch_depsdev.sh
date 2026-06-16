#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADP="$HERE/../fetch_depsdev.sh"
frag="$(bash "$ADP" --ecosystem maven --name com.zaxxer:HikariCP --version 5.1.0 \
  --raw-file "$HERE/fixtures/raw/depsdev.HikariCP.json")"

[ "$(echo "$frag" | jq -r '.source')" = "depsdev" ] || { echo "source"; exit 1; }
[ "$(echo "$frag" | jq -r '.ok')" = "true" ] || { echo "ok"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["licensing.license"].value')" = "Apache-2.0" ] || { echo "license"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["adoption.dependents"].value')" = "8123" ] || { echo "dependents"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["security.scorecard"].value')" = "7.8" ] || { echo "scorecard"; exit 1; }
# every signal carries a citation url
n="$(echo "$frag" | jq '[.signals[] | select((.citations|length)==0)] | length')"
[ "$n" = "0" ] || { echo "missing citations on $n signals"; exit 1; }
echo "test_fetch_depsdev ok"
