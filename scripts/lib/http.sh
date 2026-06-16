#!/usr/bin/env bash
# HTTP GET with cache, retry/backoff, Retry-After, and optional auth header.
# Source after common.sh and cache.sh.
# http_get <provider> <url> [ttl_seconds]
#   provider "anon" => no auth. Otherwise creds.sh header <provider> is attached if a key exists.
# Honours OSS_ADVISOR_NO_CACHE=1 and OSS_ADVISOR_REFRESH=1.

HTTP_MAX_RETRIES="${OSS_ADVISOR_HTTP_RETRIES:-4}"
CREDS_SH_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/creds.sh"

http_get() {
  local provider="$1" url="$2" ttl="${3:-86400}"
  local key="$provider/$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')"

  if [ "${OSS_ADVISOR_NO_CACHE:-0}" != "1" ] && [ "${OSS_ADVISOR_REFRESH:-0}" != "1" ]; then
    local cached
    if cached="$(cache_get "$key" "$ttl")"; then printf '%s' "$cached"; return 0; fi
  fi

  local creds_sh="${OSS_ADVISOR_CREDS_SH:-$CREDS_SH_DEFAULT}"
  local -a auth=()
  if [ "$provider" != "anon" ] && bash "$creds_sh" has "$provider" 2>/dev/null; then
    auth=(-H "$(bash "$creds_sh" header "$provider")")
  fi

  local attempt=0 delay=1 http_code body tmp
  tmp="$(mktemp)"
  while :; do
    attempt=$((attempt+1))
    http_code="$(curl -sS -w '%{http_code}' -o "$tmp" \
      -H 'Accept: application/json' -H 'User-Agent: oss-advisor' \
      "${auth[@]}" "$url" 2>/dev/null || echo 000)"
    if [ "$http_code" = "200" ]; then
      body="$(cat "$tmp")"; rm -f "$tmp"
      printf '%s' "$body" | cache_set "$key"
      printf '%s' "$body"
      return 0
    fi
    if [ "$attempt" -ge "$HTTP_MAX_RETRIES" ] || { [ "$http_code" != "429" ] && [ "${http_code:0:1}" != "5" ] && [ "$http_code" != "000" ]; }; then
      warn "http_get $provider $url -> HTTP $http_code (giving up after $attempt)"
      rm -f "$tmp"; return 1
    fi
    warn "http_get $url -> $http_code, retry $attempt in ${delay}s"
    sleep "$delay"; delay=$(( delay * 2 ))
  done
}
