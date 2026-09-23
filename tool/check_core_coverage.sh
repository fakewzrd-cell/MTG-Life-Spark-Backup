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

# lcov 2.x may exit non-zero when function/branch data is missing even if lines
# extracted cleanly — ignore that and judge coverage from the line records.
set +e
lcov --ignore-errors empty,mismatch,unused \
  --extract coverage/lcov.info "${PATTERNS[@]}" \
  -o coverage/core.lcov
extract_rc=$?
set -e

if [[ ! -s coverage/core.lcov ]]; then
  echo "Core extract produced an empty coverage/core.lcov (lcov exit $extract_rc)"
  exit 1
fi

# Parse line hit/found totals from the extracted tracefile (stable across lcov versions).
LINE_PCT=$(awk '
  /^LF:/ { lf += substr($0, 4) + 0 }
  /^LH:/ { lh += substr($0, 4) + 0 }
  END {
    if (lf <= 0) { print ""; exit 1 }
    printf "%.1f", (100.0 * lh) / lf
  }
' coverage/core.lcov)

if [[ -z "$LINE_PCT" ]]; then
  echo "Could not parse line coverage from coverage/core.lcov"
  exit 1
fi

echo "Core lines: ${LINE_PCT}% (from coverage/core.lcov)"

awk -v pct="$LINE_PCT" -v min="$MIN_PCT" 'BEGIN {
  if (pct + 0 < min + 0) {
    printf "Core line coverage %.1f%% is below minimum %.1f%%\n", pct, min;
    exit 1;
  }
  printf "Core line coverage %.1f%% meets minimum %.1f%%\n", pct, min;
  exit 0;
}'
