#!/bin/bash
#
# fastconnect_limits.sh
#
# Shows OCI service limits and current usage for FastConnect.
# Designed to run in OCI Cloud Shell (oci CLI + jq are pre-installed and
# already authenticated, so no config file or profile is needed).
#
# Usage:
#   ./fastconnect_limits.sh                       # tenancy root, current region
#   ./fastconnect_limits.sh -c <compartment-ocid>  # specific compartment
#   ./fastconnect_limits.sh -a                     # check all subscribed regions
#
# Requires: oci cli, jq

set -euo pipefail

SERVICE_NAME="fast-connect"
COMPARTMENT_ID=""
ALL_REGIONS=false

usage() {
    echo "Usage: $0 [-c compartment_ocid] [-a]"
    echo "  -c   Compartment OCID to check (default: tenancy root)"
    echo "  -a   Check all subscribed regions (default: current Cloud Shell region only)"
    exit 1
}

while getopts "c:ah" opt; do
    case "$opt" in
        c) COMPARTMENT_ID="$OPTARG" ;;
        a) ALL_REGIONS=true ;;
        h|*) usage ;;
    esac
done

if ! command -v oci >/dev/null 2>&1; then
    echo "Error: oci CLI not found. Run this in OCI Cloud Shell or install the CLI." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found." >&2
    exit 1
fi

# Default to the tenancy root compartment (Cloud Shell sets OCI_TENANCY)
if [[ -z "$COMPARTMENT_ID" ]]; then
    if [[ -n "${OCI_TENANCY:-}" ]]; then
        COMPARTMENT_ID="$OCI_TENANCY"
    else
        COMPARTMENT_ID=$(oci iam compartment list --compartment-id-in-subtree false --raw-output 2>/dev/null \
            | jq -r '.data[0]."compartment-id"' 2>/dev/null || true)
        if [[ -z "$COMPARTMENT_ID" || "$COMPARTMENT_ID" == "null" ]]; then
            # Fall back: ask for the tenancy OCID directly from the current session
            COMPARTMENT_ID=$(oci iam region-subscription list --query 'data[0]."tenancy-id"' --raw-output 2>/dev/null || true)
        fi
    fi
fi

if [[ -z "$COMPARTMENT_ID" ]]; then
    echo "Error: could not determine tenancy/compartment OCID. Pass one with -c." >&2
    exit 1
fi

echo "Compartment: $COMPARTMENT_ID"
echo "Service:     $SERVICE_NAME"
echo

# Determine which regions to query
if $ALL_REGIONS; then
    REGIONS=$(oci iam region-subscription list --query 'data[*]."region-name"' --raw-output | jq -r '.[]')
else
    REGIONS=$(oci iam region list --query 'data[0]."name"' --raw-output >/dev/null 2>&1; echo "${OCI_REGION:-$(oci setup config-file-parameter --list 2>/dev/null | true)}")
    # Simplest reliable way in Cloud Shell: use the region the CLI is currently configured for
    REGIONS=$(oci iam region-subscription list --query "data[?\"is-home-region\"==\`true\`]|[0].\"region-name\"" --raw-output 2>/dev/null || true)
    if [[ -z "$REGIONS" || "$REGIONS" == "null" ]]; then
        REGIONS=$(oci iam region-subscription list --query 'data[0]."region-name"' --raw-output)
    fi
fi

for REGION in $REGIONS; do
    echo "=================================================================="
    echo "Region: $REGION"
    echo "=================================================================="

    # Get all FastConnect limit name/value pairs in this region.
    # (The "value" field here IS the limit itself -- resource-availability
    # does not return it, it only returns used/available.)
    LIMITS_JSON=$(oci limits value list \
        --compartment-id "$COMPARTMENT_ID" \
        --service-name "$SERVICE_NAME" \
        --region "$REGION" \
        --all 2>/dev/null || true)

    LIMIT_COUNT=$(echo "$LIMITS_JSON" | jq -r '.data | length' 2>/dev/null || echo 0)

    if [[ -z "$LIMITS_JSON" || "$LIMIT_COUNT" == "0" ]]; then
        echo "No FastConnect limits found in this region for this compartment."
        echo
        continue
    fi

    printf "%-45s %10s %10s %10s\n" "LIMIT NAME" "LIMIT" "USED" "AVAILABLE"
    printf "%-45s %10s %10s %10s\n" "----------" "-----" "----" "---------"

    # Iterate name + value pairs together (tab-separated)
    while IFS=$'\t' read -r LIMIT_NAME LIMIT_VAL; do
        [[ -z "$LIMIT_NAME" ]] && continue

        AVAIL_JSON=$(oci limits resource-availability get \
            --compartment-id "$COMPARTMENT_ID" \
            --service-name "$SERVICE_NAME" \
            --limit-name "$LIMIT_NAME" \
            --region "$REGION" 2>/dev/null || true)

        AVAILABLE="n/a"
        USED="n/a"

        if [[ -n "$AVAIL_JSON" ]]; then
            AVAILABLE=$(echo "$AVAIL_JSON" | jq -r '.data.available // empty')
            USED=$(echo "$AVAIL_JSON" | jq -r '.data.used // empty')
        fi

        # A limit of 0 with no usage data just means nothing is provisioned/entitled
        [[ -z "$AVAILABLE" ]] && AVAILABLE=$([[ "$LIMIT_VAL" == "0" ]] && echo 0 || echo "n/a")
        [[ -z "$USED" ]] && USED=$([[ "$LIMIT_VAL" == "0" ]] && echo 0 || echo "n/a")

        # Derive used from limit - available when possible
        if [[ "$USED" == "n/a" && "$AVAILABLE" != "n/a" && "$LIMIT_VAL" != "n/a" ]]; then
            USED=$((LIMIT_VAL - AVAILABLE))
        fi

        printf "%-45s %10s %10s %10s\n" "$LIMIT_NAME" "$LIMIT_VAL" "$USED" "$AVAILABLE"
    done < <(echo "$LIMITS_JSON" | jq -r '.data[] | [.name, (.value|tostring)] | @tsv' | sort -u)

    echo
done
