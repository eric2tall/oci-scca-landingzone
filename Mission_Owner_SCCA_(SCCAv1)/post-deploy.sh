#!/bin/bash
# post-deploy.sh — Run after tf-apply to complete manual configuration steps
# Usage: cd ~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_(SCCAv1) && ./post-deploy.sh

set -e


# Read resource label from tfvars
RESOURCE_LABEL=$(grep "resource_label" terraform.tfvars | awk -F'"' '{print $2}')
echo "======================================================"
echo "  VA Locator Post-Deploy Configuration"
echo "======================================================"

# ── Read OCIDs from Terraform outputs ────────────────────
echo ""
echo ">>> Reading Terraform outputs..."
cd ~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_\(SCCAv1\)

BASTION_OCID=$(terraform output -raw bastion_ocid)
DRG_ID=$(terraform output -raw drg_id)
HOME_COMPARTMENT_ID=$(terraform output -raw home_compartment_id)
WORKLOAD_COMPARTMENT_ID=$(terraform output -raw workload_compartment_id)
WORKLOAD_VCN_ID=$(terraform output -raw workload_vcn_id)
WORKLOAD_SUBNET_ID=$(terraform output -raw workload_subnet_id)
VDSS_LB_SUBNET_ID=$(terraform output -raw vdss_lb_subnet_id)

echo "Bastion:    $BASTION_OCID"
echo "DRG:        $DRG_ID"
echo "Workload Compartment: $WORKLOAD_COMPARTMENT_ID"
echo "Workload VCN: $WORKLOAD_VCN_ID"

# ── Get VDSS Compartment ID ───────────────────────────────
echo ""
echo ">>> Getting VDSS compartment..."
VDSS_COMPARTMENT_ID=$(oci iam compartment list \
  --compartment-id "$HOME_COMPARTMENT_ID" \
  --all 2>/dev/null | jq -r --arg label "$RESOURCE_LABEL" '.data[] | select(.name | test("VDSS-IAD-" + $label)) | .id')
echo "VDSS Compartment: $VDSS_COMPARTMENT_ID"

# ── Update NFW subnet (SUB1) route table ─────────────────
echo ""
echo ">>> Updating NFW subnet route table with workload route..."
RT_NFW=$(oci network route-table list \
  --compartment-id "$VDSS_COMPARTMENT_ID" \
  --all 2>/dev/null | jq -r '.data[] | select(.["display-name"] | contains("SUB1")) | .id')

if [ -z "$RT_NFW" ]; then
  echo "ERROR: Could not find NFW subnet route table"
  exit 1
fi

oci network route-table update \
  --rt-id "$RT_NFW" \
  --route-rules "[
    {\"destination\":\"all-iad-services-in-oracle-services-network\",\"destinationType\":\"SERVICE_CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"all_service\"},
    {\"destination\":\"192.168.1.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"vdms\"},
    {\"destination\":\"192.168.3.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"workload_db\"},
    {\"destination\":\"192.168.0.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"vdss\"},
    {\"destination\":\"192.168.2.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"workload\"}
  ]" --force 2>/dev/null | jq -r '.data["route-rules"][] | .description + " -> " + .destination'
echo "NFW route table updated."

# ── Create or get Service Gateway ────────────────────────
echo ""
echo ">>> Setting up Service Gateway on Workload VCN..."
SGW=$(oci network service-gateway list \
  --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
  --vcn-id "$WORKLOAD_VCN_ID" \
  --all 2>/dev/null | jq -r '.data[0].id // empty')

if [ -z "$SGW" ]; then
  echo "Creating Service Gateway..."
  SERVICE_ID=$(oci network service list 2>/dev/null | jq -r '.data[] | select(.name | contains("All")) | .id')
  SGW=$(oci network service-gateway create \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --services "[{\"serviceId\":\"$SERVICE_ID\"}]" \
    --display-name "VA-EHRM-VCN-IAD-SGW" \
    2>/dev/null | jq -r '.data.id')
  echo "Service Gateway created: $SGW"
else
  echo "Service Gateway already exists: $SGW"
fi

# ── Create or get NAT Gateway ────────────────────────────
echo ""
echo ">>> Setting up NAT Gateway on Workload VCN..."
NAT=$(oci network nat-gateway list \
  --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
  --vcn-id "$WORKLOAD_VCN_ID" \
  --all 2>/dev/null | jq -r '.data[0].id // empty')

if [ -z "$NAT" ]; then
  echo "Creating NAT Gateway..."
  NAT=$(oci network nat-gateway create \
    --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
    --vcn-id "$WORKLOAD_VCN_ID" \
    --display-name "VA-EHRM-NAT-IAD-001" \
    --block-traffic false \
    2>/dev/null | jq -r '.data.id')
  echo "NAT Gateway created: $NAT"
else
  echo "NAT Gateway already exists: $NAT"
fi

# ── Add public subnet CIDR to Workload VCN ───────────────
echo ""
echo ">>> Adding public subnet CIDR to Workload VCN..."
EXISTING_CIDRS=$(oci network vcn get --vcn-id "$WORKLOAD_VCN_ID" 2>/dev/null | jq -r '.data["cidr-blocks"][]')
if echo "$EXISTING_CIDRS" | grep -q "192.168.4.0/24"; then
  echo "Public CIDR 192.168.4.0/24 already exists."
else
  oci network vcn add-vcn-cidr --vcn-id "$WORKLOAD_VCN_ID" --cidr-block "192.168.4.0/24"
  echo "Added 192.168.4.0/24 to Workload VCN."
fi

# ── Update Workload route table ───────────────────────────
echo ""
echo ">>> Updating Workload route table..."
RT_WL=$(oci network route-table list \
  --compartment-id "$WORKLOAD_COMPARTMENT_ID" \
  --vcn-id "$WORKLOAD_VCN_ID" \
  --all 2>/dev/null | jq -r '.data[] | select(.["display-name"] | test("RT-IAD")) | .id')

if [ -z "$RT_WL" ]; then
  echo "ERROR: Could not find Workload route table"
  exit 1
fi

oci network route-table update \
  --rt-id "$RT_WL" \
  --route-rules "[
    {\"destination\":\"all-iad-services-in-oracle-services-network\",\"destinationType\":\"SERVICE_CIDR_BLOCK\",\"networkEntityId\":\"$SGW\",\"description\":\"all_service\"},
    {\"destination\":\"192.168.1.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"vdms\"},
    {\"destination\":\"192.168.3.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"workload_db\"},
    {\"destination\":\"192.168.0.0/24\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$DRG_ID\",\"description\":\"vdss\"},
    {\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$NAT\",\"description\":\"nat\"}
  ]" --force 2>/dev/null | jq -r '.data["route-rules"][] | .description + " -> " + .destination'
echo "Workload route table updated."

# ── Update oke-tunnel.sh with new Bastion OCID ───────────
echo ""
echo ">>> Updating oke-tunnel.sh with new Bastion OCID..."
TUNNEL_SCRIPT=~/gitrepos/va-locator-oke/scripts/oke-tunnel.sh
if [ -f "$TUNNEL_SCRIPT" ]; then
  sed -i '' "s|BASTION_ID=.*|BASTION_ID=\"$BASTION_OCID\"|" "$TUNNEL_SCRIPT"
  echo "Tunnel script updated."
else
  echo "WARNING: Tunnel script not found at $TUNNEL_SCRIPT"
fi


echo ""
echo "======================================================"
echo "  Post-deploy configuration complete!"
echo "======================================================"
echo ""
echo "Next steps:"
echo "  1. cd ~/gitrepos/va-locator-oke/terraform && terraform apply -auto-approve"
echo "  2. ssh-add ~/.ssh/id_ed25519 && oci-tunnel"
echo "  3. kubectl get nodes"
echo "  4. cd ~/gitrepos/va-locator-oke/scripts && OCI_AUTH_TOKEN='sq}4QwwqQBHv_ho6+r0Y' ./deploy.sh"
