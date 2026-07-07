#!/bin/bash
# pre_destroy.sh — Clean up manually-created resources before tf-nuke
# Usage: cd ~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_(SCCAv1) && ./pre_destroy.sh

SCCA_DIR=~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_\(SCCAv1\)

echo "======================================================"
echo "  Pre-Destroy Cleanup"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

cd "$SCCA_DIR"

# ── Get OCIDs from Terraform outputs ─────────────────────
echo ""
echo ">>> Reading Terraform outputs..."
HOME_COMPARTMENT_ID=$(terraform output -raw home_compartment_id 2>/dev/null || echo "")
WORKLOAD_COMPARTMENT_ID=$(terraform output -raw workload_compartment_id 2>/dev/null || echo "")
WORKLOAD_VCN_ID=$(terraform output -raw workload_vcn_id 2>/dev/null || echo "")

if [ -z "$HOME_COMPARTMENT_ID" ]; then
  echo "WARNING: Could not read Terraform outputs. Some cleanup may be skipped."
fi

# ── Get VDSS Compartment ─────────────────────────────────
VDSS_COMPARTMENT_ID=""
if [ -n "$HOME_COMPARTMENT_ID" ]; then
  VDSS_COMPARTMENT_ID=$(oci iam compartment list \
    --compartment-id "$HOME_COMPARTMENT_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.name | contains("VDSS")) | .id' | head -1)
fi

# ── Delete OCI Load Balancers (created by OKE) ───────────
echo ""
echo ">>> Deleting OCI Load Balancers..."
if [ -n "$WORKLOAD_COMPARTMENT_ID" ]; then
  LB_IDS=$(oci lb load-balancer list \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["lifecycle-state"] != "DELETED") | .id')
  for LB_ID in $LB_IDS; do
    echo "Deleting LB: $LB_ID"
    oci lb load-balancer delete \
      --load-balancer-id "$LB_ID" \
      --force \
      --wait-for-state SUCCEEDED \
      --max-wait-seconds 300 2>/dev/null && echo "LB deleted." || echo "LB delete failed or already gone."
  done
else
  echo "No workload compartment found, skipping LB cleanup."
fi

# ── Delete NAT Gateway ────────────────────────────────────
echo ""
echo ">>> Deleting NAT Gateway..."
if [ -n "$WORKLOAD_COMPARTMENT_ID" ] && [ -n "$WORKLOAD_VCN_ID" ]; then
  NAT_IDS=$(oci network nat-gateway list \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["lifecycle-state"] != "TERMINATED") | .id')
  for NAT_ID in $NAT_IDS; do
    echo "Deleting NAT Gateway: $NAT_ID"
    oci network nat-gateway delete \
      --nat-gateway-id "$NAT_ID" \
      --force 2>/dev/null && echo "NAT Gateway deleted." || echo "Already gone."
  done
fi

# ── Delete Service Gateway ────────────────────────────────
echo ""
echo ">>> Deleting Service Gateway..."
if [ -n "$WORKLOAD_COMPARTMENT_ID" ] && [ -n "$WORKLOAD_VCN_ID" ]; then
  SGW_IDS=$(oci network service-gateway list \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["lifecycle-state"] != "TERMINATED") | .id')
  for SGW_ID in $SGW_IDS; do
    echo "Deleting Service Gateway: $SGW_ID"
    oci network service-gateway delete \
      --service-gateway-id "$SGW_ID" \
      --force 2>/dev/null && echo "Service Gateway deleted." || echo "Already gone."
  done
fi

# ── Delete Public Subnet ──────────────────────────────────
echo ""
echo ">>> Deleting public subnet..."
if [ -n "$WORKLOAD_COMPARTMENT_ID" ] && [ -n "$WORKLOAD_VCN_ID" ]; then
  PUB_SUBNET_IDS=$(oci network subnet list \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["display-name"] | contains("PUBLIC")) | .id')
  for SUBNET_ID in $PUB_SUBNET_IDS; do
    echo "Deleting public subnet: $SUBNET_ID"
    oci network subnet delete \
      --subnet-id "$SUBNET_ID" \
      --force 2>/dev/null && echo "Public subnet deleted." || echo "Already gone."
  done
fi

# ── Delete Internet Gateway ───────────────────────────────
echo ""
echo ">>> Deleting Internet Gateway..."
if [ -n "$WORKLOAD_COMPARTMENT_ID" ] && [ -n "$WORKLOAD_VCN_ID" ]; then
  IGW_IDS=$(oci network internet-gateway list \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["lifecycle-state"] != "TERMINATED") | .id')
  for IGW_ID in $IGW_IDS; do
    echo "Deleting Internet Gateway: $IGW_ID"
    oci network internet-gateway delete \
      --ig-id "$IGW_ID" \
      --force 2>/dev/null && echo "Internet Gateway deleted." || echo "Already gone."
  done
fi

# ── Delete Public Route Table ─────────────────────────────
echo ""
echo ">>> Deleting public route table..."
if [ -n "$WORKLOAD_COMPARTMENT_ID" ] && [ -n "$WORKLOAD_VCN_ID" ]; then
  RT_IDS=$(oci network route-table list \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["display-name"] | contains("PUBLIC")) | .id')
  for RT_ID in $RT_IDS; do
    echo "Deleting public route table: $RT_ID"
    oci network route-table delete \
      --rt-id "$RT_ID" \
      --force 2>/dev/null && echo "Route table deleted." || echo "Already gone."
  done
fi

# ── Remove extra VCN CIDRs ────────────────────────────────
echo ""
echo ">>> Removing extra VCN CIDRs..."
if [ -n "$WORKLOAD_VCN_ID" ]; then
  EXTRA_CIDRS=$(oci network vcn get \
    --vcn-id "$WORKLOAD_VCN_ID" \
    2>/dev/null | jq -r '.data["cidr-blocks"][] | select(. != "192.168.2.0/24")')
  for CIDR in $EXTRA_CIDRS; do
    echo "Removing CIDR: $CIDR"
    oci network vcn remove-vcn-cidr \
      --vcn-id "$WORKLOAD_VCN_ID" \
      --cidr-block "$CIDR" 2>/dev/null && echo "CIDR removed." || echo "Already gone."
  done
fi

# ── Delete NFW Policies (unattached) ─────────────────────
echo ""
echo ">>> Deleting unattached NFW policies..."
if [ -n "$VDSS_COMPARTMENT_ID" ]; then
  NFW_POLICY_IDS=$(oci network-firewall network-firewall-policy list \
    --compartment-id "$VDSS_COMPARTMENT_ID" \
    --all 2>/dev/null | jq -r '.data.items[] | select(.["lifecycle-state"] == "ACTIVE") | .id')
  
  # Get attached policy ID
  NFW_ID=$(oci network-firewall network-firewall list \
    --compartment-id "$VDSS_COMPARTMENT_ID" \
    --all 2>/dev/null | jq -r '.data.items[0].["network-firewall-policy-id"] // empty')

  for POLICY_ID in $NFW_POLICY_IDS; do
    if [ "$POLICY_ID" != "$NFW_ID" ]; then
      echo "Deleting unattached NFW policy: $POLICY_ID"
      oci network-firewall network-firewall-policy delete \
        --network-firewall-policy-id "$POLICY_ID" \
        --force 2>/dev/null && echo "Policy deleted." || echo "Could not delete."
    fi
  done
fi

# ── Deactivate Identity Domain ────────────────────────────
echo ""
echo ">>> Deactivating Identity Domain..."
if [ -n "$HOME_COMPARTMENT_ID" ]; then
  DOMAIN_IDS=$(oci iam domain list \
    --compartment-id "$HOME_COMPARTMENT_ID" \
    --all 2>/dev/null | jq -r '.data[] | select(.["lifecycle-state"] == "ACTIVE" and .type == "DEFAULT") | .id')
  for DOMAIN_ID in $DOMAIN_IDS; do
    echo "Deactivating domain: $DOMAIN_ID"
    oci iam domain deactivate \
      --domain-id "$DOMAIN_ID" \
      --wait-for-state SUCCEEDED \
      --max-wait-seconds 300 2>/dev/null && echo "Domain deactivated." || echo "Already inactive or failed."
  done
fi

# ── Clean up Object Storage Buckets ──────────────────────
echo ""
echo ">>> Cleaning up Object Storage buckets..."
if [ -n "$HOME_COMPARTMENT_ID" ]; then
  BUCKETS=$(oci os bucket list \
    --compartment-id "$HOME_COMPARTMENT_ID" \
    --all 2>/dev/null | jq -r '.data[].name')
  for BUCKET in $BUCKETS; do
    echo "Deleting bucket: $BUCKET"
    # Delete all objects first
    oci os object bulk-delete --bucket-name "$BUCKET" --force 2>/dev/null || true
    oci os bucket delete --bucket-name "$BUCKET" --force 2>/dev/null && echo "Bucket deleted." || echo "Could not delete."
  done
fi

echo ""
echo "======================================================"
echo "  Pre-destroy cleanup complete!"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"
