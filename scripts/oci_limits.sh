#!/usr/bin/env bash
set -euo pipefail

# --- Auto-detect tenancy OCID (Cloud Shell has no ~/.oci/config file; it uses
#     instance-principal auth instead, so we try a few fallbacks) ---
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
  echo "  TENANCY_OCID=ocid1.tenancy.oc1..xxxx ./oci_limits.sh" >&2
  exit 1
fi
echo "Tenancy OCID: $TENANCY_OCID"

# --- Auto-detect every region this tenancy is subscribed to ---
echo "Looking up subscribed regions..."
mapfile -t REGIONS < <(oci iam region-subscription list \
  --tenancy-id "$TENANCY_OCID" \
  | jq -r '.data[]."region-name"')

if [[ ${#REGIONS[@]} -eq 0 ]]; then
  echo "ERROR: no subscribed regions found" >&2
  exit 1
fi
echo "Found ${#REGIONS[@]} region(s): ${REGIONS[*]}"
echo

OUT="oci_limit_values_by_region.csv"
echo "region,service,limit_name,scope_type,availability_domain,current_limit" > "$OUT"

TOTAL_ROWS=0
REGION_IDX=0

for region in "${REGIONS[@]}"; do
  REGION_IDX=$((REGION_IDX + 1))
  echo "=== Region [$REGION_IDX/${#REGIONS[@]}]: $region ==="

  echo "  Fetching service list..."
  mapfile -t SERVICES < <(oci limits service list \
    --compartment-id "$TENANCY_OCID" \
    --region "$region" \
    --all | jq -r '.data[].name')

  NUM_SERVICES=${#SERVICES[@]}
  echo "  Found $NUM_SERVICES service(s) in $region"

  SVC_IDX=0
  REGION_ROWS=0

  for svc in "${SERVICES[@]}"; do
    SVC_IDX=$((SVC_IDX + 1))
    printf "  [%d/%d] %-30s ... " "$SVC_IDX" "$NUM_SERVICES" "$svc"

    ROWS=$(oci limits value list \
      --compartment-id "$TENANCY_OCID" \
      --region "$region" \
      --service-name "$svc" \
      --all 2>/dev/null \
    | jq -r --arg region "$region" --arg svc "$svc" \
      '.data[] | [
        $region,
        $svc,
        .name,
        (."scope-type" // ""),
        (."availability-domain" // ""),
        (.value // "")
      ] | @csv' || true)

    if [[ -n "$ROWS" ]]; then
      echo "$ROWS" >> "$OUT"
      N=$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')
      REGION_ROWS=$((REGION_ROWS + N))
      TOTAL_ROWS=$((TOTAL_ROWS + N))
      echo "$N row(s)"
    else
      echo "no data"
    fi
  done

  echo "  -> $region done: $REGION_ROWS row(s)"
  echo
done

echo "Export complete: $OUT ($TOTAL_ROWS total rows across ${#REGIONS[@]} region(s))"
