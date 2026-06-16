#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export OSS_ADVISOR_CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$OSS_ADVISOR_CACHE_DIR"' EXIT
. "$HERE/../lib/common.sh"
. "$HERE/../lib/cache.sh"
. "$HERE/../lib/http.sh"

url="https://example.test/api/thing"
# Pre-seed cache so http_get returns it without any network call.
key="anon/$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')"
echo '{"cached":true}' | cache_set "$key"
out="$(http_get anon "$url" 600)"
[ "$(echo "$out" | jq -r '.cached')" = "true" ] || { echo "expected cache hit: $out"; exit 1; }
echo "test_http ok"
