#!/usr/bin/env bash
set -euo pipefail
# --- Auto-detect tenancy OCID (same fallback chain as the other scripts) ---
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
  echo "ERROR: could not auto-detect tenancy OCID. Set it manually, e.g.:" >&2
  echo "  TENANCY_OCID=ocid1.tenancy.oc2..aaaaaaaa6wmvw62q6s4zfsthrisvuxkjf4qkiya3miybnbuvpbrhelvshgra ./check_oci_limits.sh" >&2
  exit 1
fi
echo "Tenancy OCID: $TENANCY_OCID"
echo

# --- Limits flagged as >=20x current -> requested (check real usage against them) ---
EXTREME=(
  "analytics|ee-ocpu-count|4|128"
  "analytics|ee-user-count|100|2000"
  "api-gateway|certificate-count|1|50"
  "autonomous-recovery-service|protected-database-backup-storage-gb|10240|1000000"
  "compute|standard-e4-core-count|6|250"
  "compute|standard-e4-memory-count|96|8192"
  "compute|standard-e5-core-count|25|500"
  "data-science|ds-block-volume-gb|300|10000"
  "data-science|ds-standard-e5-core-regional-count|4|128"
  "data-science|ds-standard-e5-memory-count|64|4096"
  "database|adw-total-storage-tb|16|512"
  "database|atp-ecpu-count|8|512"
  "load-balancer|lb-flexible-bandwidth-sum|500|10000"
  "network-load-balancer-api|max-nlb-flexible-count|1|25"
  "service-connector-hub|service-connector-count|2|50"
)

# --- Limits requested only in us-langley-1, check if they're even valid resources in us-luke-1 ---
MISSING_PAIR=(
  "container-engine|enhanced-cluster-count"
  "container-engine|node-count"
  "data-science|notebook-session-count"
  "open-search|master-node-count"
  "open-search|opendashboard-node-count"
  "waf|policy-count"
)

OUT="oci_usage_check.csv"
echo "region,service,limit_name,used,available,effective_quota,current_request_limit,requested_limit,status" > "$OUT"

REGIONS=(us-langley-1 us-luke-1)
TOTAL=0
FAILED=0

for region in "${REGIONS[@]}"; do
  echo "=== Region: $region ==="

  for entry in "${EXTREME[@]}"; do
    IFS='|' read -r service limit cur req <<< "$entry"
    result=$(oci limits resource-availability get \
      --compartment-id "$TENANCY_OCID" \
      --service-name "$service" \
      --limit-name "$limit" \
      --region "$region" \
      --output json 2>/dev/null || echo "ERROR")
    if [[ "$result" == "ERROR" ]]; then
      echo "  - $service/$limit: LOOKUP FAILED"
      jq -rn --arg r "$region" --arg s "$service" --arg l "$limit" --arg req "$req" \
        '[$r,$s,$l,"","","","",$req,"LOOKUP_FAILED"] | @csv' >> "$OUT"
      FAILED=$((FAILED + 1))
      continue
    fi
    used=$(jq -r '.data.used // "n/a"' <<< "$result")
    avail=$(jq -r '.data.available // "n/a"' <<< "$result")
    quota=$(jq -r '.data."effective-quota-value" // "n/a"' <<< "$result")
    echo "  - $service/$limit: used=$used available=$avail (current=$cur -> requested=$req)"
    jq -rn --arg r "$region" --arg s "$service" --arg l "$limit" --arg u "$used" --arg a "$avail" \
      --arg q "$quota" --arg c "$cur" --arg req "$req" \
      '[$r,$s,$l,$u,$a,$q,$c,$req,"OK"] | @csv' >> "$OUT"
    TOTAL=$((TOTAL + 1))
  done

  if [[ "$region" == "us-luke-1" ]]; then
    echo "  -- checking Langley-only limits for validity in us-luke-1 --"
    for entry in "${MISSING_PAIR[@]}"; do
      IFS='|' read -r service limit <<< "$entry"
      result=$(oci limits resource-availability get \
        --compartment-id "$TENANCY_OCID" \
        --service-name "$service" \
        --limit-name "$limit" \
        --region "$region" \
        --output json 2>/dev/null || echo "ERROR")
      if [[ "$result" == "ERROR" ]]; then
        echo "  - $service/$limit: NOT AVAILABLE in us-luke-1"
        jq -rn --arg r "$region" --arg s "$service" --arg l "$limit" \
          '[$r,$s,$l,"","","","0","0","NOT_AVAILABLE_IN_LUKE"] | @csv' >> "$OUT"
      else
        used=$(jq -r '.data.used // "n/a"' <<< "$result")
        avail=$(jq -r '.data.available // "n/a"' <<< "$result")
        quota=$(jq -r '.data."effective-quota-value" // "n/a"' <<< "$result")
        echo "  - $service/$limit: VALID but not requested (used=$used available=$avail)"
        jq -rn --arg r "$region" --arg s "$service" --arg l "$limit" --arg u "$used" --arg a "$avail" \
          --arg q "$quota" \
          '[$r,$s,$l,$u,$a,$q,"0","0","VALID_BUT_NOT_REQUESTED"] | @csv' >> "$OUT"
      fi
      TOTAL=$((TOTAL + 1))
    done
  fi
  echo
done

echo "Done: $OUT ($TOTAL lookup(s) recorded, $FAILED failed)"
echo
echo "Note: 'used'/'available' come from the Limits resource-availability API and reflect"
echo "current utilization at the time this ran -- not historical growth. A low 'used' value"
echo "for a newly-migrating workload doesn't necessarily mean the requested increase is"
echo "oversized; it may just mean the migration hasn't landed yet."
