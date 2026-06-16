#!/usr/bin/env bash
# Run all available adapters for one package and merge fragments into facts.json.
# Usage: collect.sh --ecosystem <e> --name <n> [--version <v>] [--repo <url>]
#                   [--policy-file <p>] [--fragments-file <f>]   (test seam: skip adapters, merge given fragments)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"

ECO=""; NAME=""; VER=""; REPO=""; POLICY_FILE=""; FRAG_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version) VER="$2"; shift 2;; --repo) REPO="$2"; shift 2;;
  --policy-file) POLICY_FILE="$2"; shift 2;; --fragments-file) FRAG_FILE="$2"; shift 2;; *) shift;; esac; done

# Per-key precedence: ordered list of sources; first non-null value wins.
PRECEDENCE='{
  "licensing.license":["depsdev","registry","librariesio"],
  "adoption.dependents":["depsdev","librariesio"],
  "adoption.downloads_recent":["registry","librariesio"],
  "security.scorecard":["depsdev","snyk"],
  "security.osv_queried":["osv"],
  "security.open_cves":["osv"],
  "security.max_cvss":["osv"],
  "security.unpatched_critical":["osv"],
  "compatibility.transitive_conflict_risk":["depsdev","socket"]
}'
DEFAULT_ORDER='["osv","github","depsdev","registry","librariesio","snyk","socket"]'

if [ -n "$FRAG_FILE" ]; then
  fragments="$(cat "$FRAG_FILE")"
else
  coords="$(bash "$HERE/resolve.sh" --ecosystem "$ECO" --name "$NAME" ${VER:+--version "$VER"})"
  [ -z "$REPO" ] && REPO="$(echo "$coords" | jq -r '.repo_url // empty')"
  args=(--ecosystem "$ECO" --name "$NAME"); [ -n "$VER" ] && args+=(--version "$VER")
  # Run each adapter; collect fragments (failures still emit ok:false fragments).
  frags=()
  for adp in fetch_osv fetch_github fetch_depsdev fetch_registry fetch_librariesio fetch_snyk fetch_socket; do
    # Fallback fragment uses the adapter's short name (strip fetch_ prefix) and a placeholder
    # fetched_at so degraded provenance matches emit_fragment output.
    if [ "$adp" = "fetch_github" ]; then
      frags+=("$(bash "$HERE/$adp.sh" --repo "$REPO" "${args[@]}" 2>/dev/null || echo '{"source":"'"${adp#fetch_}"'","ok":false,"fetched_at":null,"signals":{},"notes":["adapter error"]}')")
    else
      frags+=("$(bash "$HERE/$adp.sh" "${args[@]}" 2>/dev/null || echo '{"source":"'"${adp#fetch_}"'","ok":false,"fetched_at":null,"signals":{},"notes":["adapter error"]}')")
    fi
  done
  fragments="$(printf '%s\n' "${frags[@]}" | jq -s '.')"
fi

policy='{}'
[ -n "$POLICY_FILE" ] && policy="$(cat "$POLICY_FILE")"

# Merge with precedence. For each signal key, choose value from the highest-precedence source
# that provides a non-null value; stamp .source. Union of all keys across ok fragments.
echo "$fragments" | jq \
  --arg eco "$ECO" --arg name "$NAME" --arg ver "$VER" \
  --argjson prec "$PRECEDENCE" --argjson deforder "$DEFAULT_ORDER" --argjson policy "$policy" '
  . as $frags
  | [ $frags[] | select(.ok==true) ] as $ok
  | ( [ $ok[] | .signals | keys[] ] | unique ) as $keys
  | ( reduce $keys[] as $k ({};
      ($prec[$k] // $deforder) as $order
      | ( [ $order[] as $src
            | ($ok[] | select(.source==$src) | .signals[$k] // empty
               | select(.value != null) | . + {source:$src}) ]
          | .[0] ) as $chosen
      | if $chosen == null then . else . + { ($k): $chosen } end
    ) ) as $signals
  | {
      coordinates: { ecosystem:$eco, name:$name, version:(if $ver=="" then null else $ver end) },
      signals: $signals,
      sources_used: ([ $ok[].source ] | unique),
      sources_degraded: ([ $frags[] | select(.ok==false) | .source ] | unique),
      policy: $policy
    }'
