#!/usr/bin/env bash
set -uo pipefail
TENANCY_OCID="${OCI_CLI_TENANCY:-}"
if [[ -z "$TENANCY_OCID" && -f "$HOME/.oci/config" ]]; then
  TENANCY_OCID=$(awk -F'=' '/^tenancy[[:space:]]*=/{gsub(/ /,"",$2); print $2; exit}' "$HOME/.oci/config")
fi
if [[ -z "$TENANCY_OCID" ]]; then
  TENANCY_OCID=$(oci iam compartment list \
    --query 'data[?contains("compartment-id", `.tenancy`)]."compartment-id" | [0]' \
    --raw-output 2>/dev/null)
fi
if [[ -z "$TENANCY_OCID" || "$TENANCY_OCID" == "null" ]]; then
  echo "ERROR: could not auto-detect tenancy OCID." >&2
  exit 1
fi
echo "Tenancy OCID: $TENANCY_OCID"
echo

HOURS_BACK="${HOURS_BACK:-8}"
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START=$(date -u -d "${HOURS_BACK} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${HOURS_BACK}H +%Y-%m-%dT%H:%M:%SZ)
echo "Searching audit events from $START to $END (root compartment, last ${HOURS_BACK}h) ..."
echo

RAW=$(oci audit event list \
  --compartment-id "$TENANCY_OCID" \
  --start-time "$START" \
  --end-time "$END" \
  --all \
  --output json 2>&1)
RC=$?

if [[ $RC -ne 0 ]]; then
  echo "Command failed (exit $RC). Raw output:"
  echo "$RAW" | sed 's/^/  /' | head -20
  exit 1
fi
if ! jq empty <<< "$RAW" 2>/dev/null; then
  echo "Didn't get valid JSON back. Raw output:"
  echo "$RAW" | sed 's/^/  /' | head -20
  exit 1
fi

TOTAL=$(jq '.data | length' <<< "$RAW")
echo "=== $TOTAL total audit events -- keyword search across the whole event, not just specific fields ==="
MATCHES=$(jq -r '
  .data[]
  | select(tostring | test("CrossConnect|VirtualCircuit|Drg|FastConnect|Fast Connect"; "i"))
  | "  [\(.["event-time"])] status=\(.data.response.status // "n/a") message=\(.data.response.message // "n/a")\n    raw: \(. | tostring | .[0:300])"
' <<< "$RAW" 2>/dev/null)
if [[ -z "$MATCHES" ]]; then
  echo "  Still no FastConnect/CrossConnect/VirtualCircuit/Drg keyword anywhere in these $TOTAL events."
  echo "  That means the create attempt either happened outside this window, or in a compartment this"
  echo "  audit query isn't covering (audit event list only searches the exact compartment given, not children)."
else
  echo "$MATCHES"
fi
echo

echo "=== Billing/subscription-related failures in this window (relevant given the expired trial) ==="
jq -r '
  .data[]
  | select(tostring | test("Billing|Configuration|Subscription|Credit"; "i"))
  | select((.data.response.status // 200 | tonumber) >= 400)
  | "  [\(.["event-time"])] status=\(.data.response.status) message=\(.data.response.message // "n/a")"
' <<< "$RAW" 2>/dev/null | sort -u | head -20
echo

echo "=== All 4xx/5xx failures in this window, deduped by message ==="
jq -r '
  .data[]
  | select((.data.response.status // 200 | tonumber) >= 400)
  | "\(.data.response.status)|\(.data.response.message // "n/a")"
' <<< "$RAW" 2>/dev/null | sort | uniq -c | sort -rn | head -20
