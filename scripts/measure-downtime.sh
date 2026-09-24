#!/bin/bash
set -e

# Measures what clients see while a deploy or rollback runs.
# Start this from any machine, then push to main (or run rollback.sh) while it runs.
#
#   bash scripts/measure-downtime.sh http://your-server 180 8
#
# Args: base URL, duration in seconds (default 120), parallel workers (default 4)

BASE_URL=${1%/}
DURATION=${2:-120}
WORKERS=${3:-4}

if [ -z "$BASE_URL" ]; then
    echo "Error: Base URL required (e.g., http://203.0.113.10)."
    exit 1
fi

URL="$BASE_URL/version"
OUT_DIR=$(mktemp -d)
END=$(( $(date +%s) + DURATION ))

echo "Hitting $URL with $WORKERS workers for ${DURATION}s..."

# Each worker logs one line per request: <epoch-ms> <http-code> <commit>
for (( w=1; w<=WORKERS; w++ )); do
    (
        while [ "$(date +%s)" -lt "$END" ]; do
            RESPONSE=$(curl -s --max-time 5 -w ' %{http_code}' "$URL" 2>/dev/null || echo ' 000')
            CODE=${RESPONSE##* }
            COMMIT=$(echo "$RESPONSE" | sed -n 's/.*"commit":"\([^"]*\)".*/\1/p')
            echo "$(date +%s%3N) $CODE ${COMMIT:--}"
        done > "$OUT_DIR/worker-$w.log"
    ) &
done
wait

sort -n "$OUT_DIR"/worker-*.log > "$OUT_DIR/all.log"

awk '
    {
        if (!start) start = $1
        total++
        if ($2 != 200) {
            failed++
            if (!first_fail) first_fail = $1
            last_fail = $1
        }
        if ($2 == 200 && $3 != commit) {
            if (commit != "") printf "  +%.1fs  commit %s -> %s\n", ($1 - start) / 1000, commit, $3
            commit = $3
        }
    }
    END {
        print ""
        printf "Requests sent:     %d\n", total
        printf "Failed (non-200):  %d\n", failed
        printf "Success rate:      %.3f%%\n", total ? (total - failed) * 100 / total : 0
        if (failed) printf "Failure window:    %d ms (first to last failed request)\n", last_fail - first_fail
    }
' "$OUT_DIR/all.log"

echo ""
echo "Raw log: $OUT_DIR/all.log"
