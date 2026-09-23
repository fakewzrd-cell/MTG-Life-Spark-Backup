#!/usr/bin/env bash
# Requires: flutter test --coverage (produces coverage/lcov.info)
#           lcov (apt install lcov / brew install lcov)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MIN_PCT="${MIN_CORE_COVERAGE_PCT:-45}"

if [[ ! -f coverage/lcov.info ]]; then
  echo "Missing coverage/lcov.info — run: flutter test --coverage"
  exit 1
fi

if ! command -v lcov >/dev/null 2>&1; then
  echo "lcov not installed; skipping core coverage gate"
  exit 0
fi

# Flutter writes relative SF paths (lib/core/...). Older absolute paths also match
# via the leading * form; lcov 2.x warns/fails if a listed pattern matches nothing.
PATTERNS=('lib/core/*')
if grep -q '^SF:/.*/lib/core/' coverage/lcov.info 2>/dev/null; then
  PATTERNS+=('*/lib/core/*')
fi

lcov --ignore-errors empty,mismatch \
  --extract coverage/lcov.info "${PATTERNS[@]}" \
  -o coverage/core.lcov
SUMMARY=$(lcov --summary --ignore-errors empty,mismatch coverage/core.lcov 2>&1)
echo "$SUMMARY"

LINE_PCT=$(echo "$SUMMARY" | awk '/lines.*:/ { gsub(/%/, "", $2); print $2; exit }')
if [[ -z "$LINE_PCT" ]]; then
  echo "Could not parse line coverage from lcov summary"
  exit 1
fi

awk -v pct="$LINE_PCT" -v min="$MIN_PCT" 'BEGIN {
  if (pct + 0 < min + 0) {
    printf "Core line coverage %.1f%% is below minimum %.1f%%\n", pct, min;
    exit 1;
  }
  printf "Core line coverage %.1f%% meets minimum %.1f%%\n", pct, min;
  exit 0;
}'
