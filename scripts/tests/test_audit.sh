#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AUD="$HERE/../audit.sh"
M="$HERE/fixtures/manifests"

npm_out="$(bash "$AUD" --file "$M/package.json")"
[ "$(echo "$npm_out" | jq -r 'length')" = "3" ] || { echo "npm count"; exit 1; }
[ "$(echo "$npm_out" | jq -r '.[] | select(.name=="express") | .ecosystem')" = "npm" ] || { echo "npm eco"; exit 1; }
[ "$(echo "$npm_out" | jq -r '.[] | select(.name=="express") | .version')" = "4.18.2" ] || { echo "npm ver strip"; exit 1; }

py_out="$(bash "$AUD" --file "$M/requirements.txt")"
[ "$(echo "$py_out" | jq -r 'length')" = "3" ] || { echo "py count (comment + VCS line excluded)"; exit 1; }
[ "$(echo "$py_out" | jq -r '.[] | select(.name=="requests") | .version')" = "2.31.0" ] || { echo "py ver"; exit 1; }
# VCS/editable line must be skipped (no bogus package name)
[ "$(echo "$py_out" | jq -r '[.[] | select(.name | test("git|://|^-"))] | length')" = "0" ] || { echo "py VCS line not skipped"; exit 1; }

mvn_out="$(bash "$AUD" --file "$M/pom.xml")"
[ "$(echo "$mvn_out" | jq -r 'length')" = "2" ] || { echo "mvn count"; exit 1; }
[ "$(echo "$mvn_out" | jq -r '.[0].name')" = "com.zaxxer:HikariCP" ] || { echo "mvn name"; exit 1; }
[ "$(echo "$mvn_out" | jq -r '.[0].ecosystem')" = "maven" ] || { echo "mvn eco"; exit 1; }
echo "test_audit ok"
