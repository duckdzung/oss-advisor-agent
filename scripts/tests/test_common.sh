#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"

# now_iso looks like an ISO-8601 Z timestamp
ts="$(now_iso)"
[[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "bad ts: $ts"; exit 1; }

# emit_fragment builds valid JSON with the given source and ok flag
frag="$(emit_fragment depsdev true '{"adoption.stars":{"value":5,"citations":[]}}' '[]')"
[ "$(echo "$frag" | jq -r '.source')" = "depsdev" ] || { echo "source wrong"; exit 1; }
[ "$(echo "$frag" | jq -r '.ok')" = "true" ] || { echo "ok wrong"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["adoption.stars"].value')" = "5" ] || { echo "signal wrong"; exit 1; }

# ecosystem_ok accepts known, rejects unknown
ecosystem_ok npm || { echo "npm should be ok"; exit 1; }
if ecosystem_ok bogus; then echo "bogus should fail"; exit 1; fi
echo "test_common ok"
