#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADP="$HERE/../fetch_osv.sh"
frag="$(bash "$ADP" --ecosystem npm --name left-pad-evil --version 0.0.1 \
  --raw-file "$HERE/fixtures/raw/osv.vulns.json")"

[ "$(echo "$frag" | jq -r '.signals["security.osv_queried"].value')" = "true" ] || { echo "queried"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["security.open_cves"].value')" = "2" ] || { echo "open_cves"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["security.max_cvss"].value')" = "9.8" ] || { echo "max_cvss"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["security.unpatched_critical"].value')" = "true" ] || { echo "unpatched"; exit 1; }
echo "test_fetch_osv ok"
