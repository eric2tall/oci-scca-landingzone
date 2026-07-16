#!/usr/bin/env bash
set -euo pipefail

# ---- Config ----
TENANCY_OCID="ocid1.tenancy.oc2..aaaaaaaa6wmvw62q6s4zfsthrisvuxkjf4qkiya3miybnbuvpbrhelvshgra"
SUBSCRIPTION_OCID="ocid1.organizationssubscription.oc2.us-langley-1.amaaaaaainyenyyari6uf5dkms2uxmln37zphf6joy5wun4u7bbvysyfms5a"

SUB_JSON="./subscription_detail_raw.json"

echo "=== Fetching subscription + commitment details ==="
echo ""

oci osub-subscription subscription subscription list \
  --compartment-id "$TENANCY_OCID" \
  --subscription-id "$SUBSCRIPTION_OCID" \
  --is-commit-info-required true \
  --all \
  > "$SUB_JSON"

echo "Saved raw response -> $SUB_JSON"
echo ""
echo "--- Full response (non-null fields only) ---"
jq 'walk(if type == "object" then with_entries(select(.value != null)) else . end)' "$SUB_JSON"

echo ""
echo "--- Attempting to surface funded / used / remaining amounts ---"
jq -r '
  .data[]? // .data // {}
  | .. 
  | objects
  | to_entries[]
  | select(.key | test("fund|commit|used|remain|balance|value|amount"; "i"))
  | "\(.key): \(.value)"
' "$SUB_JSON" | sort -u
