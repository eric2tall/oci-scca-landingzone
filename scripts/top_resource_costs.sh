#!/usr/bin/env bash
set -euo pipefail

# ---- Config ----
TENANCY_OCID="ocid1.tenancy.oc2..aaaaaaaa6wmvw62q6s4zfsthrisvuxkjf4qkiya3miybnbuvpbrhelvshgra"

# ---- Defaults ----
DEFAULT_THRESHOLD=10
DEFAULT_START="$(date +%Y-%m-01)"   # first day of current month
DEFAULT_END="$(date +%Y-%m-%d)"     # today

# ---- Helper: validate YYYY-MM-DD ----
validate_date() {
  if ! [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Error: date must be in YYYY-MM-DD format (got: $1)" >&2
    exit 1
  fi
}

# ---- Determine threshold/dates: from args, or prompt interactively with defaults ----
# Usage: ./top_resource_costs.sh [threshold] [start_date] [end_date]
if [ $# -ge 1 ]; then
  THRESHOLD="$1"
else
  read -rp "Minimum cost to report [${DEFAULT_THRESHOLD}]: " THRESHOLD
  THRESHOLD="${THRESHOLD:-$DEFAULT_THRESHOLD}"
fi

if [ $# -ge 2 ]; then
  START_DATE="$2"
else
  read -rp "Start date (YYYY-MM-DD) [${DEFAULT_START}]: " START_DATE
  START_DATE="${START_DATE:-$DEFAULT_START}"
fi

if [ $# -ge 3 ]; then
  END_DATE="$3"
else
  read -rp "End date (YYYY-MM-DD) [${DEFAULT_END}]: " END_DATE
  END_DATE="${END_DATE:-$DEFAULT_END}"
fi

# ---- Validate inputs ----
if ! [[ "$THRESHOLD" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Error: threshold must be a positive number (e.g. 10 or 10.50)" >&2
  exit 1
fi
validate_date "$START_DATE"
validate_date "$END_DATE"

START="${START_DATE}T00:00:00.000Z"
END="${END_DATE}T00:00:00.000Z"

RAW_JSON="./usage_by_resource_raw.json"

echo "Fetching usage data grouped by resource (this may take a moment)..."

oci usage-api usage-summary request-summarized-usages \
  --tenant-id "$TENANCY_OCID" \
  --time-usage-started "$START" \
  --time-usage-ended "$END" \
  --granularity MONTHLY \
  --group-by '["resourceId","service"]' \
  --query "data.items" \
  > "$RAW_JSON"

echo ""
echo "Top resource costs over \$${THRESHOLD} (${START_DATE} to ${END_DATE}):"
echo ""

jq -r --argjson threshold "$THRESHOLD" '
  # Normalize possible key spellings (CLI output uses hyphenated keys)
  map({
    resourceId:   (.["resource-id"] // .resourceId // "unknown"),
    service:      (.service // "unknown"),
    amount:       (.["computed-amount"] // .computedAmount // 0)
  })
  # Group by resource identity
  | group_by(.resourceId)
  | map({
      resource: (.[0].resourceId),
      service:  (.[0].service),
      total:    (map(.amount // 0) | add)
    })
  | map(select(.total > $threshold))
  | sort_by(-.total)
  | .[]
  | [(.total * 100 | round / 100 | tostring), .service, .resource]
  | @tsv
' "$RAW_JSON" | awk -F'\t' '
  BEGIN { printf "%-12s %-30s %s\n", "AMOUNT", "SERVICE", "RESOURCE (OCID)"; printf "%-12s %-30s %s\n", "------", "-------", "---------------" }
  { printf "$%-11s %-30s %s\n", $1, $2, $3 }
'

echo ""
echo "Done. Raw grouped data saved to: $RAW_JSON"
