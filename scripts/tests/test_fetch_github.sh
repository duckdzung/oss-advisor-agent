#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADP="$HERE/../fetch_github.sh"
frag="$(bash "$ADP" --repo https://github.com/brettwooldridge/HikariCP \
  --raw-file "$HERE/fixtures/raw/github.repo.json")"
[ "$(echo "$frag" | jq -r '.signals["adoption.stars"].value')" = "20100" ] || { echo "stars"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["health.last_commit_days"].value')" = "20" ] || { echo "days=$(echo "$frag" | jq -r '.signals["health.last_commit_days"].value')"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["security.has_security_md"].value')" = "true" ] || { echo "secmd"; exit 1; }
# bus_factor = contributors with >5% share = 3 (0.42,0.18,0.11)
[ "$(echo "$frag" | jq -r '.signals["health.bus_factor"].value')" = "3" ] || { echo "bus"; exit 1; }
echo "test_fetch_github ok"
