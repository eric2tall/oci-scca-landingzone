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

echo "=== Subscription(s) assigned to this tenancy ==="
RAW=$(oci organizations assigned-subscription list --compartment-id "$TENANCY_OCID" --all --output json 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
  echo "Command failed (exit $RC). Raw output:"
  echo "$RAW" | sed 's/^/  /' | head -30
  exit 1
fi
if ! jq empty <<< "$RAW" 2>/dev/null; then
  echo "Didn't get valid JSON back. Raw output:"
  echo "$RAW" | sed 's/^/  /' | head -30
  exit 1
fi

COUNT=$(jq '.data.items | length' <<< "$RAW" 2>/dev/null || echo 0)
if [[ "$COUNT" -eq 0 ]]; then
  echo "No assigned subscriptions found for this tenancy. Full response:"
  echo "$RAW" | jq .
  exit 0
fi

echo "  ($COUNT assigned subscription(s) found)"
echo "$RAW" | jq -r '.data.items[] | "
  Classic Subscription ID: \(.["classic-subscription-id"] // "n/a")
  Subscription OCID:       \(.id // "n/a")
  Service Name:            \(.["service-name"] // "n/a")
  Lifecycle State:         \(.["lifecycle-state"] // "n/a")
  Start Date:              \(.["start-date"] // "n/a")
  End Date:                \(.["end-date"] // "n/a")
"'
