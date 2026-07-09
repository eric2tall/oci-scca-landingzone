#!/usr/bin/env bash
set -euo pipefail

# --- Auto-detect tenancy OCID (same fallback chain as the limits script) ---
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
  echo "  TENANCY_OCID=ocid1.tenancy.oc1..xxxx ./oci_tenancy_inventory.sh" >&2
  exit 1
fi
echo "Tenancy OCID: $TENANCY_OCID"

# --- Build a compartment-id -> compartment-name lookup so the report is readable ---
echo "Building compartment name lookup..."
CMAP_FILE=$(mktemp)
oci iam compartment list \
  --compartment-id "$TENANCY_OCID" \
  --compartment-id-in-subtree true \
  --all \
  --query 'data[].{id:id,name:name}' \
| jq 'map({(.id): .name}) | add // {}' \
| jq --arg t "$TENANCY_OCID" '. + {($t): "(root)"}' > "$CMAP_FILE"

NUM_COMPARTMENTS=$(jq 'length' "$CMAP_FILE")
echo "Found $NUM_COMPARTMENTS compartment(s) (including root)"
echo

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

OUT="oci_tenancy_inventory.csv"
echo "region,resource_type,display_name,compartment_name,compartment_id,lifecycle_state,availability_domain,time_created,identifier" > "$OUT"

TOTAL=0
REGION_IDX=0

for region in "${REGIONS[@]}"; do
  REGION_IDX=$((REGION_IDX + 1))
  echo "=== Region [$REGION_IDX/${#REGIONS[@]}]: $region ==="

  # structured-search has no --all flag; it pages via --limit/--page and
  # returns a top-level "opc-next-page" token when there's more data.
  NEXT_PAGE=""
  PAGE_NUM=0
  REGION_COUNT=0

  while :; do
    PAGE_NUM=$((PAGE_NUM + 1))
    echo "  Searching all resources (page $PAGE_NUM)..."

    if [[ -n "$NEXT_PAGE" ]]; then
      RESPONSE=$(oci search resource structured-search \
        --query-text "query all resources" \
        --region "$region" \
        --limit 1000 \
        --page "$NEXT_PAGE" 2>/dev/null)
    else
      RESPONSE=$(oci search resource structured-search \
        --query-text "query all resources" \
        --region "$region" \
        --limit 1000 2>/dev/null)
    fi

    ROWS=$(printf '%s' "$RESPONSE" | jq -r --slurpfile cmap "$CMAP_FILE" --arg region "$region" '
        ($cmap[0]) as $c |
        .data.items[]? | [
          $region,
          .["resource-type"],
          (.["display-name"] // ""),
          ($c[.["compartment-id"]] // .["compartment-id"]),
          .["compartment-id"],
          (.["lifecycle-state"] // ""),
          (.["availability-domain"] // ""),
          (.["time-created"] // ""),
          .identifier
        ] | @csv
      ' 2>/dev/null || true)

    if [[ -n "$ROWS" ]]; then
      echo "$ROWS" >> "$OUT"
      COUNT=$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')
      REGION_COUNT=$((REGION_COUNT + COUNT))
      echo "    -> $COUNT resource(s) on this page"
    fi

    NEXT_PAGE=$(printf '%s' "$RESPONSE" | jq -r '."opc-next-page" // empty' 2>/dev/null)
    [[ -z "$NEXT_PAGE" ]] && break
  done

  if [[ $REGION_COUNT -eq 0 ]]; then
    echo "  no resources found in $region"
  else
    echo "  -> $REGION_COUNT resource(s) total in $region"
  fi
  TOTAL=$((TOTAL + REGION_COUNT))
  echo
done

rm -f "$CMAP_FILE"
echo "Inventory complete: $OUT ($TOTAL total resources across ${#REGIONS[@]} region(s))"
