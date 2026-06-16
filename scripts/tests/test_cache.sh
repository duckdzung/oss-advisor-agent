#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OSS_ADVISOR_CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$OSS_ADVISOR_CACHE_DIR"' EXIT
. "$HERE/../lib/common.sh"
. "$HERE/../lib/cache.sh"

key="depsdev/test-key"
# miss on empty cache
if cache_get "$key" 60 >/dev/null 2>&1; then echo "should miss"; exit 1; fi
# set then hit within TTL
echo '{"x":1}' | cache_set "$key"
out="$(cache_get "$key" 60)"
[ "$(echo "$out" | jq -r '.x')" = "1" ] || { echo "hit wrong: $out"; exit 1; }
# expired (TTL 0) -> miss
if cache_get "$key" 0 >/dev/null 2>&1; then echo "ttl0 should miss"; exit 1; fi
echo "test_cache ok"
