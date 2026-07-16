#!/usr/bin/env bash
set -euo pipefail
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
  echo "  TENANCY_OCID=ocid1.tenancy.oc2..aaaaaaaa6wmvw62q6s4zfsthrisvuxkjf4qkiya3miybnbuvpbrhelvshgra ./check_oci_ad_limits.sh" >&2
  exit 1
fi
echo "Tenancy OCID: $TENANCY_OCID"
echo

AD_LIMITS=(
  "standard-e4-core-count|6|250"
  "standard-e4-memory-count|96|8192"
  "standard-e5-core-count|25|500"
)

OUT="oci_ad_usage_check.csv"
echo "region,availability_domain,service,limit_name,used,available,effective_quota,current_request_limit,requested_limit,status" > "$OUT"

REGIONS=(us-langley-1 us-luke-1)
TOTAL=0
FAILED=0

for region in "${REGIONS[@]}"; do
  echo "=== Region: $region ==="

  ADS=$(oci iam availability-domain list \
    --compartment-id "$TENANCY_OCID" \
    --region "$region" \
    --output json 2>/dev/null | jq -r '.data[].name' || true)

  if [[ -z "$ADS" ]]; then
    echo "  could not list availability domains for $region -- skipping"
    echo
    continue
  fi

  while IFS= read -r AD; do
    echo "  -- AD: $AD --"
    for entry in "${AD_LIMITS[@]}"; do
      IFS='|' read -r limit cur req <<< "$entry"
      result=$(oci limits resource-availability get \
        --compartment-id "$TENANCY_OCID" \
        --service-name compute \
        --limit-name "$limit" \
        --availability-domain "$AD" \
        --region "$region" \
        --output json 2>/dev/null || echo "ERROR")
      if [[ "$result" == "ERROR" ]]; then
        echo "    - $limit: LOOKUP FAILED"
        jq -rn --arg r "$region" --arg ad "$AD" --arg l "$limit" --arg req "$req" \
          '[$r,$ad,"compute",$l,"","","","",$req,"LOOKUP_FAILED"] | @csv' >> "$OUT"
        FAILED=$((FAILED + 1))
        continue
      fi
      used=$(jq -r '.data.used // "n/a"' <<< "$result")
      avail=$(jq -r '.data.available // "n/a"' <<< "$result")
      quota=$(jq -r '.data."effective-quota-value" // "n/a"' <<< "$result")
      echo "    - $limit: used=$used available=$avail (current=$cur -> requested=$req)"
      jq -rn --arg r "$region" --arg ad "$AD" --arg l "$limit" --arg u "$used" --arg a "$avail" \
        --arg q "$quota" --arg c "$cur" --arg req "$req" \
        '[$r,$ad,"compute",$l,$u,$a,$q,$c,$req,"OK"] | @csv' >> "$OUT"
      TOTAL=$((TOTAL + 1))
    done
  done <<< "$ADS"
  echo
done

echo "Done: $OUT ($TOTAL lookup(s) recorded, $FAILED failed)"
