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

echo "=== Budgets configured on this tenancy ==="
RAW=$(oci budgets budget budget list --compartment-id "$TENANCY_OCID" --all --output json 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
  echo "  Command failed (exit $RC). Raw output:"
  echo "$RAW" | sed 's/^/    /' | head -20
elif jq empty <<< "$RAW" 2>/dev/null; then
  COUNT=$(jq '.data | length' <<< "$RAW")
  if [[ "$COUNT" -eq 0 ]]; then
    echo "  No budgets found."
  else
    jq -r '.data[] | "  - \(.["display-name"]): amount=\(.amount) \(.["target-type"]) actual-spend=\(.["actual-spend"] // "n/a") forecasted-spend=\(.["forecasted-spend"] // "n/a") reset-period=\(.["reset-period"])"' <<< "$RAW"
  fi
else
  echo "  Command exited 0 but didn't return valid JSON. Raw output:"
  echo "$RAW" | sed 's/^/    /' | head -20
fi
echo

echo "=== Cost/usage summary, last 30 days (by service) ==="
END=$(date -u +%Y-%m-%dT00:00:00Z)
START=$(date -u -d '30 days ago' +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v-30d +%Y-%m-%dT00:00:00Z)
RAW=$(oci usage-api usage-summary request-summarized-usages \
  --tenant-id "$TENANCY_OCID" \
  --time-usage-started "$START" \
  --time-usage-ended "$END" \
  --granularity MONTHLY \
  --query-type COST \
  --group-by '["service"]' \
  --output json 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
  echo "  Command failed (exit $RC). Raw output:"
  echo "$RAW" | sed 's/^/    /' | head -20
elif jq empty <<< "$RAW" 2>/dev/null; then
  ITEMS=$(jq '.data.items | length' <<< "$RAW" 2>/dev/null || echo 0)
  if [[ "$ITEMS" -eq 0 ]]; then
    echo "  No usage line items returned for this period."
  else
    jq -r '.data.items[] | "  - \(.service // "unknown"): $\(.computedAmount // 0)"' <<< "$RAW"
  fi
else
  echo "  Command exited 0 but didn't return valid JSON. Raw output:"
  echo "$RAW" | sed 's/^/    /' | head -20
fi
echo

echo "=== FastConnect service limits (sanity check, not a credit issue if these look fine) ==="
for region in us-langley-1 us-luke-1; do
  for limit in virtual-circuit-count remote-peering-connection-count; do
    RAW=$(oci limits resource-availability get \
      --compartment-id "$TENANCY_OCID" \
      --service-name fast-connect \
      --limit-name "$limit" \
      --region "$region" \
      --output json 2>&1)
    RC=$?
    if [[ $RC -ne 0 ]]; then
      echo "  [$region] $limit: LOOKUP FAILED -- $(echo "$RAW" | head -1)"
    elif jq empty <<< "$RAW" 2>/dev/null; then
      used=$(jq -r '.data.used // "n/a"' <<< "$RAW")
      avail=$(jq -r '.data.available // "n/a"' <<< "$RAW")
      echo "  [$region] $limit: used=$used available=$avail"
    else
      echo "  [$region] $limit: unexpected output -- $(echo "$RAW" | head -1)"
    fi
  done
done
echo

echo "If Budgets/Usage above look fine but FastConnect creation still fails with a credit/payment error,"
echo "the block is almost certainly at the subscription/billing level, which isn't visible via the oci CLI."
echo "Check Console > Governance & Administration > Account Management > Organization for balance/status,"
echo "or open a My Oracle Support (MOS) ticket against the Gov Cloud subscription."
