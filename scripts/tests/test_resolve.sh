#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
out="$(bash "$HERE/../resolve.sh" --ecosystem maven --name com.zaxxer:HikariCP --version 5.1.0 \
  --raw-file "$HERE/fixtures/raw/resolve.depsdev.json")"
[ "$(echo "$out" | jq -r '.ecosystem')" = "maven" ] || { echo "eco"; exit 1; }
[ "$(echo "$out" | jq -r '.name')" = "com.zaxxer:HikariCP" ] || { echo "name"; exit 1; }
[ "$(echo "$out" | jq -r '.repo_url')" = "https://github.com/brettwooldridge/HikariCP" ] || { echo "repo"; exit 1; }
echo "test_resolve ok"
