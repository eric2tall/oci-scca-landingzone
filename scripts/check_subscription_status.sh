#!/bin/bash
#
# check_subscription_status.sh
# Confirms OCI subscription status via CLI (mirrors Console > Billing > Subscriptions).
#
# Usage: ./check_subscription_status.sh [-c compartment_ocid] [-p plan_number]

set -euo pipefail

COMPARTMENT_ID=""
PLAN_NUMBER="76893363"   # from Billing > Subscriptions in the Console

while getopts "c:p:h" opt; do
    case "$opt" in
        c) COMPARTMENT_ID="$OPTARG" ;;
        p) PLAN_NUMBER="$OPTARG" ;;
        h|*) echo "Usage: $0 [-c compartment_ocid] [-p plan_number]"; exit 1 ;;
    esac
done

if [[ -z "$COMPARTMENT_ID" ]]; then
    COMPARTMENT_ID="${OCI_TENANCY:-}"
fi

if [[ -z "$COMPARTMENT_ID" ]]; then
    echo "Error: could not determine tenancy OCID. Pass one with -c." >&2
    exit 1
fi

echo "Compartment: $COMPARTMENT_ID"
echo "Plan number: $PLAN_NUMBER"
echo

RAW=$(oci osub-subscription subscription subscription list \
    --compartment-id "$COMPARTMENT_ID" \
    --plan-number "$PLAN_NUMBER" \
    --all 2>&1) || { echo "$RAW"; exit 1; }

echo "$RAW" > /tmp/subscription_raw.json

echo "=== Any field containing 'status' ==="
echo "$RAW" | jq '.data[] | to_entries[] | select(.key | test("status"; "i"))' 2>/dev/null \
    || echo "(could not parse -- see raw output below)"

echo
echo "=== Full record ==="
echo "$RAW" | jq '.' 2>/dev/null || echo "$RAW"
