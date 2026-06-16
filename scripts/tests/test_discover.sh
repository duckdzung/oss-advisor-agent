#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DSC="$HERE/../discover.sh"
# Offline: provide search results via --raw-file and extra LLM candidates via --candidates
out="$(bash "$DSC" --ecosystem npm --query "connection pool" \
  --raw-file "$HERE/fixtures/raw/npm.search.json" \
  --candidates '["knex","generic-pool"]')"
# union, deduped: pg-pool, generic-pool, knex
[ "$(echo "$out" | jq -r 'length')" = "3" ] || { echo "count=$(echo "$out" | jq -r 'length')"; exit 1; }
echo "$out" | jq -e '.[] | select(.name=="pg-pool")' >/dev/null || { echo "missing pg-pool"; exit 1; }
echo "$out" | jq -e 'all(.[]; .ecosystem=="npm")' >/dev/null || { echo "ecosystem stamp"; exit 1; }
# generic-pool appears once despite being in both sources
[ "$(echo "$out" | jq -r '[.[] | select(.name=="generic-pool")] | length')" = "1" ] || { echo "dedup"; exit 1; }
echo "test_discover ok"
