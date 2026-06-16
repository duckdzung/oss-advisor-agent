#!/usr/bin/env bash
# Shared helpers for OSS Advisor adapters. Source this; do not execute.

log()  { printf '[oss-advisor] %s\n' "$*" >&2; }
warn() { printf '[oss-advisor][warn] %s\n' "$*" >&2; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

KNOWN_ECOSYSTEMS="npm pypi maven go cargo nuget"
# Note: go/cargo/nuget are accepted as known ecosystems, but the registry adapter
# currently supports only npm/pypi/maven (it degrades with an ok:false note otherwise).
ecosystem_ok() {
  local e="$1"
  case " $KNOWN_ECOSYSTEMS " in *" $e "*) return 0;; *) return 1;; esac
}

# emit_fragment <source> <ok:true|false> <signals-json-object> <notes-json-array>
emit_fragment() {
  local source="$1" ok="$2" signals="${3:-}" notes="${4:-[]}"
  [ -n "$signals" ] || signals='{}'
  jq -n --arg source "$source" --argjson ok "$ok" \
        --argjson signals "$signals" --argjson notes "$notes" \
        --arg fetched_at "$(now_iso)" \
        '{source:$source, ok:$ok, fetched_at:$fetched_at, signals:$signals, notes:$notes}'
}

# signal_obj <value-json> <url> -> a {value,citations} object (url optional)
signal_obj() {
  local value="$1" url="${2:-}"
  if [ -n "$url" ]; then
    jq -n --argjson value "$value" --arg url "$url" '{value:$value, citations:[{url:$url}]}'
  else
    jq -n --argjson value "$value" '{value:$value, citations:[]}'
  fi
}
