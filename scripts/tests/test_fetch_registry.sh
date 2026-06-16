#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADP="$HERE/../fetch_registry.sh"
frag="$(bash "$ADP" --ecosystem npm --name express --version 4.18.2 \
  --raw-file "$HERE/fixtures/raw/registry.npm.json")"
[ "$(echo "$frag" | jq -r '.signals["adoption.downloads_recent"].value')" = "21000000" ] || { echo "downloads"; exit 1; }
[ "$(echo "$frag" | jq -r '.signals["licensing.license"].value')" = "MIT" ] || { echo "license"; exit 1; }
# semver_compliant inferred true when latest matches X.Y.Z
[ "$(echo "$frag" | jq -r '.signals["stability.semver_compliant"].value')" = "true" ] || { echo "semver"; exit 1; }
echo "test_fetch_registry ok"
