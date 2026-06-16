#!/usr/bin/env bash
# GitHub adapter. Uses creds.sh 'github' token when present (via http_get provider=github).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"

REPO=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --raw-file) RAW_FILE="$2"; shift 2;;
  --ecosystem|--name|--version) shift 2;; *) shift;; esac; done

if [ -n "$RAW_FILE" ]; then
  raw="$(cat "$RAW_FILE")"
  # tests embed a fixed "now"; use it for deterministic day math.
  # A non-JSON body must degrade, not crash under pipefail.
  now_epoch="$(echo "$raw" | jq -r '(.now // "2026-06-15T00:00:00Z") | fromdateiso8601' 2>/dev/null)" \
    || { emit_fragment github false '{}' '["malformed response"]'; exit 0; }
else
  [ -n "$REPO" ] || { emit_fragment github false '{}' '["no repo url"]'; exit 0; }
  slug="$(printf '%s' "$REPO" | sed -E 's#https?://github.com/##; s#/$##; s#\.git$##')"
  repo_json="$(http_get github "https://api.github.com/repos/$slug" 86400)" || { emit_fragment github false '{}' '["github repo fetch failed"]'; exit 0; }
  contrib="$(http_get github "https://api.github.com/repos/$slug/contributors?per_page=10" 86400)" || contrib='[]'
  secmd=false
  if http_get github "https://api.github.com/repos/$slug/contents/SECURITY.md" 86400 >/dev/null 2>&1; then secmd=true; fi
  total="$(echo "$contrib" | jq '[.[].contributions] | add // 0')"
  raw="$(jq -n --argjson r "$repo_json" --argjson c "$contrib" --argjson secmd "$secmd" --argjson total "$total" '
    { html_url: $r.html_url, stargazers_count: $r.stargazers_count, forks_count: $r.forks_count,
      pushed_at: $r.pushed_at, has_security_md: $secmd,
      top_contributors_share: ([ $c[]? | (if $total>0 then (.contributions/$total) else 0 end) ]) }')"
  now_epoch="$(date +%s)"
fi

signals="$(printf '%s' "$raw" | jq --argjson now_epoch "$now_epoch" '
  def now_epoch: $now_epoch;
  .html_url as $url
  | (((now_epoch - (.pushed_at | fromdateiso8601)) / 86400) | floor) as $days
  | ([ .top_contributors_share[]? | select(. > 0.05) ] | length) as $bus
  | {
      "adoption.stars": {value:(.stargazers_count // null), citations:[{url:$url}]},
      "adoption.forks": {value:(.forks_count // null), citations:[{url:$url}]},
      "health.last_commit_days": {value:$days, citations:[{url:$url}]},
      "health.bus_factor": {value:$bus, citations:[{url:$url}]},
      "health.active_maintainers": {value:$bus, citations:[{url:$url}]},
      "security.has_security_md": {value:(.has_security_md // false), citations:[{url:$url}]}
    }' 2>/dev/null)" || { emit_fragment github false '{}' '["malformed response"]'; exit 0; }
emit_fragment github true "$signals" '[]'
