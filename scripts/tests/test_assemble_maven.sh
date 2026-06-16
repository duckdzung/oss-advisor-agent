#!/usr/bin/env bash
# Guards Fix 2: assemble_maven reads the actual Maven Solr response (not jq -n null input)
# and extracts latestVersion. Exercised offline via the --assemble-raw-file seam.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ADP="$HERE/../fetch_registry.sh"

frag="$(bash "$ADP" --ecosystem maven --name com.zaxxer:HikariCP \
  --assemble-raw-file "$HERE/fixtures/raw/maven.solr.json")"

# Fragment must be valid and ok:true
printf '%s' "$frag" | jq -e . >/dev/null 2>&1 || { echo "not valid JSON"; exit 1; }
[ "$(echo "$frag" | jq -r '.ok')" = "true" ] || { echo "expected ok:true"; exit 1; }

# latest=5.1.0 -> semver_compliant should be true (transform derives it from latest X.Y.Z)
[ "$(echo "$frag" | jq -r '.signals["stability.semver_compliant"].value')" = "true" ] \
  || { echo "expected semver_compliant true for latest 5.1.0"; exit 1; }

# Also assert the assemble jq program directly yields latest=5.1.0
latest="$(jq -r '(.response.docs[0] // {}) as $d | ($d.latestVersion // null)' \
  < "$HERE/fixtures/raw/maven.solr.json")"
[ "$latest" = "5.1.0" ] || { echo "expected latest=5.1.0, got $latest"; exit 1; }

echo "test_assemble_maven ok"
