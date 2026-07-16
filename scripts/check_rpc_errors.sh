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
echo "Searching audit events from $START to $END (last ${HOURS_BACK}h) ..."
echo

RAW=$(oci audit event list \
  --compartment-id "$TENANCY_OCID" \
  --start-time "$START" \
  --end-time "$END" \
  --all \
  --output json 2>&1)
RC=$?
if [[ $RC -ne 0 ]] || ! jq empty <<< "$RAW" 2>/dev/null; then
  echo "Command failed or returned bad JSON:"
  echo "$RAW" | head -20
  exit 1
fi

echo "=== Everything mentioning RemotePeeringConnection or CreateVirtualCircuit ==="
jq -r '
  .data[]
  | select(tostring | test("RemotePeeringConnection|CreateVirtualCircuit"; "i"))
  | "  [\(.["event-time"])] status=\(.data.response.status // "n/a") message=\(.data.response.message // "n/a")"
' <<< "$RAW" 2>/dev/null | sort -u

echo
echo "=== Same, but only the failures (4xx/5xx) ==="
jq -r '
  .data[]
  | select(tostring | test("RemotePeeringConnection|CreateVirtualCircuit"; "i"))
  | select((.data.response.status // 200 | tonumber) >= 400)
  | "  [\(.["event-time"])] status=\(.data.response.status) message=\(.data.response.message // "n/a")\n    full: \(. | tostring)"
' <<< "$RAW" 2>/dev/null
