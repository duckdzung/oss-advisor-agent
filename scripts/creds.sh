#!/usr/bin/env bash
# Manage optional adapter API keys without exposing values to callers/LLM.
# Storage: JSON object at $OSS_ADVISOR_CREDS_FILE (default ~/.config/oss-advisor/creds.json), chmod 600.
# Subcommands:
#   has <provider>            exit 0 if a key exists, else 1   (no output)
#   set <provider> <secret>   store/replace a key              (no echo of value)
#   list                      print provider names only        (NEVER values)
#   header <provider>         print the HTTP auth header line   (used by http.sh only)
set -euo pipefail

CREDS_FILE="${OSS_ADVISOR_CREDS_FILE:-$HOME/.config/oss-advisor/creds.json}"
KNOWN="github librariesio snyk socket"

_ensure() {
  mkdir -p "$(dirname "$CREDS_FILE")"
  [ -f "$CREDS_FILE" ] || { umask 077; echo '{}' > "$CREDS_FILE"; }
  chmod 600 "$CREDS_FILE" 2>/dev/null || true
}

_get() { _ensure; jq -r --arg p "$1" '.[$p] // empty' "$CREDS_FILE"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  has)
    [ -n "$(_get "${1:?provider}")" ] ;;
  set)
    _ensure
    p="${1:?provider}"; secret="${2:?secret}"
    tmp="$(mktemp)"
    jq --arg p "$p" --arg v "$secret" '.[$p]=$v' "$CREDS_FILE" > "$tmp" && mv "$tmp" "$CREDS_FILE"
    chmod 600 "$CREDS_FILE" 2>/dev/null || true
    echo "Stored key for '$p' (value not displayed)." ;;
  list)
    _ensure
    echo "Known providers: $KNOWN"
    echo "Configured:"
    jq -r 'keys[]' "$CREDS_FILE" | sed 's/^/  - /' ;;
  header)
    p="${1:?provider}"; v="$(_get "$p")"
    [ -n "$v" ] || { echo "no key for $p" >&2; exit 1; }
    case "$p" in
      github)      echo "Authorization: Bearer $v" ;;
      librariesio) echo "Authorization: Bearer $v" ;;
      snyk)        echo "Authorization: token $v" ;;
      socket)      echo "Authorization: Bearer $v" ;;
      *)           echo "Authorization: Bearer $v" ;;
    esac ;;
  *)
    echo "usage: creds.sh {has|set|list|header} ..." >&2; exit 2 ;;
esac
