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

echo "=== Budgets on this tenancy ==="
RAW=$(oci budgets budget budget list --compartment-id "$TENANCY_OCID" --all --output json 2>&1)
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

COUNT=$(jq '.data | length' <<< "$RAW")
if [[ "$COUNT" -eq 0 ]]; then
  echo "  No budgets configured on this tenancy."
  echo
  echo "This means the credit issue isn't Budgets-service driven -- points back to the"
  echo "subscription/billing level (expired FREE_TRIAL subscription finding from earlier)."
  exit 0
fi

echo "  ($COUNT budget(s) found)"
jq -r '.data[] | "  - \(.["display-name"]) (id=\(.id)): amount=\(.amount) target-type=\(.["target-type"]) actual-spend=\(.["actual-spend"] // "n/a") forecasted-spend=\(.["forecasted-spend"] // "n/a") reset-period=\(.["reset-period"]) alert-rule-count=\(.["alert-rule-count"] // 0)"' <<< "$RAW"
echo

echo "=== Alert rules for each budget ==="
jq -r '.data[].id' <<< "$RAW" | while IFS= read -r BUDGET_ID; do
  NAME=$(jq -r --arg id "$BUDGET_ID" '.data[] | select(.id == $id) | .["display-name"]' <<< "$RAW")
  echo "  -- $NAME ($BUDGET_ID) --"
  ARAW=$(oci budgets budget alert-rule list --budget-id "$BUDGET_ID" --all --output json 2>&1)
  ARC=$?
  if [[ $ARC -ne 0 ]]; then
    echo "    Command failed (exit $ARC): $(echo "$ARAW" | head -3)"
    continue
  fi
  if ! jq empty <<< "$ARAW" 2>/dev/null; then
    echo "    Didn't get valid JSON back: $(echo "$ARAW" | head -3)"
    continue
  fi
  ACOUNT=$(jq '.data | length' <<< "$ARAW")
  if [[ "$ACOUNT" -eq 0 ]]; then
    echo "    No alert rules on this budget."
  else
    jq -r '.data[] | "    - type=\(.type) threshold=\(.threshold) threshold-type=\(.["threshold-type"]) message=\(.message // "n/a")"' <<< "$ARAW"
  fi
done
