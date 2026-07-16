#!/bin/bash
# nuke-all.sh — Destroy all VA Locator infrastructure
# Usage: cd ~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_(SCCAv1) && ./nuke-all.sh

SCCA_DIR=~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_\(SCCAv1\)
OKE_DIR=~/gitrepos/va-locator-oke/terraform

echo "======================================================"
echo "  VA Locator Full Teardown"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"
echo ""
read -p "WARNING: This will destroy ALL infrastructure. Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# ── Kill tunnel ───────────────────────────────────────────
echo ""
echo ">>> Killing Bastion tunnel..."
pkill -f "6443:192.168" 2>/dev/null && echo "Tunnel killed." || echo "No tunnel running."

# ── Delete k8s namespace ──────────────────────────────────
echo ""
echo ">>> Deleting Kubernetes namespace..."
kubectl delete namespace va-locator 2>/dev/null && echo "Namespace deleted." || echo "Namespace not found or tunnel not running."

# ── Destroy OKE ───────────────────────────────────────────
echo ""
echo ">>> Destroying OKE cluster and node pool..."
cd "$OKE_DIR"
terraform destroy -auto-approve 2>/dev/null || echo "OKE destroy had errors — continuing..."

# ── Pre-destroy cleanup ───────────────────────────────────
echo ""
echo ">>> Running pre-destroy cleanup..."
cd "$SCCA_DIR"
./pre_destroy.sh 2>/dev/null || echo "Pre-destroy had errors — continuing..."

# ── Destroy SCCA ──────────────────────────────────────────
echo ""
echo ">>> Destroying SCCA Landing Zone..."
cd "$SCCA_DIR"
terraform destroy -var-file="terraform.tfvars" -auto-approve

echo ""
echo "======================================================"
echo "  Teardown Complete!"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"
