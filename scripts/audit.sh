#!/usr/bin/env bash
# Parse a dependency manifest into a JSON array of {ecosystem,name,version}.
# Detects type by filename; supports package.json, requirements.txt, pom.xml.
set -euo pipefail

FILE=""
while [ $# -gt 0 ]; do case "$1" in --file) FILE="$2"; shift 2;; *) shift;; esac; done
[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 2; }
base="$(basename "$FILE")"

case "$base" in
  package.json)
    jq '[ (.dependencies // {}) + (.devDependencies // {}) | to_entries[]
          | { ecosystem:"npm", name:.key, version:(.value | sub("^[\\^~>=< ]*";"")) } ]' "$FILE"
    ;;
  requirements.txt)
    out="[]"
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [ -z "$line" ] && continue
      case "$line" in -*|*"://"*) continue;; esac
      name="$(printf '%s' "$line" | sed -E 's/[<>=!~].*$//')"
      ver="$(printf '%s' "$line" | sed -nE 's/^[^=]*==([0-9][^,;]*).*/\1/p')"
      out="$(echo "$out" | jq --arg n "$name" --arg v "$ver" '. + [ {ecosystem:"pypi", name:$n, version:(if $v=="" then null else $v end)} ]')"
    done < "$FILE"
    echo "$out"
    ;;
  pom.xml)
    python3 - "$FILE" <<'PY'
import sys, json, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
ns = ""
if root.tag.startswith("{"):
    ns = root.tag[:root.tag.index("}")+1]
out = []
for dep in root.iter(ns + "dependency"):
    g = dep.findtext(ns + "groupId")
    a = dep.findtext(ns + "artifactId")
    v = dep.findtext(ns + "version")
    if g and a:
        out.append({"ecosystem": "maven", "name": "%s:%s" % (g, a), "version": v})
print(json.dumps(out))
PY
    ;;
  *)
    echo "unsupported manifest: $base" >&2; exit 2 ;;
esac
