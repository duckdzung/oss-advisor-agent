#!/usr/bin/env bash
# Resolve canonical coordinates + source repo URL. Output: {ecosystem,name,version,repo_url}.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/cache.sh"; . "$HERE/lib/http.sh"

ECO=""; NAME=""; VER=""; RAW_FILE=""
while [ $# -gt 0 ]; do case "$1" in
  --ecosystem) ECO="$2"; shift 2;; --name) NAME="$2"; shift 2;;
  --version) VER="$2"; shift 2;; --raw-file) RAW_FILE="$2"; shift 2;; *) shift;; esac; done

ecosystem_ok "$ECO" || { echo "unknown ecosystem: $ECO" >&2; exit 2; }

depsdev_system() { case "$1" in npm) echo NPM;; pypi) echo PYPI;; maven) echo MAVEN;; go) echo GO;; cargo) echo CARGO;; nuget) echo NUGET;; esac; }
if [ -n "$RAW_FILE" ]; then raw="$(cat "$RAW_FILE")"; else
  url="https://deps.dev/_/s/$(depsdev_system "$ECO")/p/$(printf %s "$NAME" | jq -sRr @uri)"
  raw="$(http_get anon "$url" 604800)" || raw='{}'
fi
repo="$(printf '%s' "$raw" | jq -r '
  (.version.projects[]? | select(.type=="GITHUB") | "https://github.com/" + .name) // empty' | head -n1)"
jq -n --arg e "$ECO" --arg n "$NAME" --arg v "$VER" --arg r "$repo" \
  '{ecosystem:$e, name:$n, version:(if $v=="" then null else $v end), repo_url:(if $r=="" then null else $r end)}'
