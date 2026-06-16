#!/usr/bin/env bash
# Runs every tests/test_*.sh; each is a standalone script that exits non-zero on failure.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$HERE"/test_*.sh; do
  echo "== $(basename "$t") =="
  if bash "$t"; then echo "PASS"; else echo "FAIL"; fail=1; fi
done
exit "$fail"
