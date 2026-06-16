#!/usr/bin/env bash
# File cache with TTL. Source after common.sh.

cache_dir() { echo "${OSS_ADVISOR_CACHE_DIR:-$HOME/.cache/oss-advisor}"; }

# cache_path <key> -> filesystem path (key may contain '/')
cache_path() {
  local key="$1"
  local safe
  safe="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._/-' '_')"
  echo "$(cache_dir)/$safe.json"
}

# cache_get <key> <ttl_seconds> : prints cached body if fresh, else returns 1
cache_get() {
  local key="$1" ttl="$2" path
  path="$(cache_path "$key")"
  [ -f "$path" ] || return 1
  local mtime now age
  mtime="$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null)"
  now="$(date +%s)"
  age="$(( now - mtime ))"
  [ "$age" -lt "$ttl" ] || return 1
  cat "$path"
}

# cache_set <key> : reads body from stdin, writes to cache
cache_set() {
  local key="$1" path
  path="$(cache_path "$key")"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}
