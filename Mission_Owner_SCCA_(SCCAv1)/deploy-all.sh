#!/bin/bash
# deploy-all.sh — Full VA Locator deployment from scratch
# Usage: cd ~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_(SCCAv1) && ./deploy-all.sh

set -e

SCCA_DIR=~/gitrepos/oci-scca-landingzone/Mission_Owner_SCCA_\(SCCAv1\)
OKE_DIR=~/gitrepos/va-locator-oke/terraform
SCRIPTS_DIR=~/gitrepos/va-locator-oke/scripts

echo "======================================================"
echo "  VA Locator Full Deployment"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ── STEP 1: SCCA Landing Zone ─────────────────────────────
echo ""
echo ">>> STEP 1: Deploying SCCA Landing Zone..."
cd "$SCCA_DIR"
terraform apply -var-file="terraform.tfvars" -auto-approve
echo "SCCA Landing Zone deployed."

# ── STEP 2: Post-Deploy Configuration ────────────────────
echo ""
echo ">>> STEP 2: Running post-deploy configuration..."
cd "$SCCA_DIR"
./post-deploy.sh
echo "Post-deploy configuration complete."

# ── STEP 3: NFW Policy Upgrade (manual) ──────────────────
echo ""
echo "======================================================"
echo "  MANUAL STEP REQUIRED — NFW Policy Upgrade"
echo "======================================================"
echo ""
echo "  1. Open OCI Console"
echo "  2. Go to Identity & Security -> Network Firewalls -> Network Firewall Policies"
echo "  3. Select compartment VA-VDSS-IAD-$(terraform output -raw identity_domain_name 2>/dev/null | sed 's/OCI-SCCA-LZ-Domain-IAD-//' || echo 'devX')"
echo "  4. Click 'network-firewall-policy'"
echo "  5. Click 'Upgrade policy' and wait for Active status"
echo "  6. Verify Rules tab shows: allow-vdms, allow-workload, reject-all-rule"
echo ""
read -p "Press ENTER when NFW policy upgrade is complete..." 

# ── STEP 4: OKE Cluster ───────────────────────────────────
echo ""
echo ">>> STEP 4: Deploying OKE Cluster and Node Pool..."
cd "$OKE_DIR"
terraform apply -auto-approve

# Get new OKE endpoint
OKE_ENDPOINT=$(terraform output -raw oke_private_endpoint 2>/dev/null | cut -d: -f1)
CLUSTER_ID=$(terraform output -raw cluster_id)
echo "OKE Cluster deployed. Endpoint: $OKE_ENDPOINT"

# Update tunnel script with new OKE IP
sed -i '' "s|OKE_IP=.*|OKE_IP=\"$OKE_ENDPOINT\"|" "$SCRIPTS_DIR/oke-tunnel.sh"
echo "Tunnel script updated with new OKE IP."

# ── STEP 5: Regenerate kubeconfig ────────────────────────
echo ""
echo ">>> STEP 5: Generating kubeconfig..."
oci ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_ID" \
  --file ~/.kube/config \
  --region us-ashburn-1 \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT
sed -i '' "s|https://${OKE_ENDPOINT}:6443|https://127.0.0.1:6443|" ~/.kube/config
echo "kubeconfig updated."

# ── STEP 6: Build and Push Docker Images ─────────────────
echo ""
echo ">>> STEP 6: Building and pushing Docker images..."
cd "$SCRIPTS_DIR"
OCI_AUTH_TOKEN="sq}4QwwqQBHv_ho6+r0Y" ./push_images.sh
echo "Images pushed to OCIR."

# ── STEP 7: Open Bastion Tunnel ───────────────────────────
echo ""
echo ">>> STEP 7: Opening Bastion tunnel..."
"$SCRIPTS_DIR/oke-tunnel.sh" &
TUNNEL_PID=$!
echo "Tunnel PID: $TUNNEL_PID"
sleep 10

# Verify tunnel
if ! kubectl get nodes &>/dev/null; then
  echo "ERROR: Tunnel not working. Check SSH key with: ssh-add ~/.ssh/id_ed25519"
  kill $TUNNEL_PID 2>/dev/null
  exit 1
fi
echo "Tunnel working. Nodes:"
kubectl get nodes

# ── STEP 8: Deploy App ────────────────────────────────────
echo ""
echo ">>> STEP 8: Deploying VA Locator app..."
cd "$SCRIPTS_DIR"
OCI_AUTH_TOKEN="sq}4QwwqQBHv_ho6+r0Y" ./deploy.sh

# ── DONE ─────────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  Deployment Complete!"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "  App URL (private LB): $(kubectl get svc va-locator-frontend -n va-locator -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
echo ""
echo "  To access locally:"
echo "  kubectl port-forward svc/va-locator-frontend 8080:80 -n va-locator"
echo "  Open: http://localhost:8080"
echo ""
echo "  Tunnel is running in background (PID: $TUNNEL_PID)"
echo "  To stop tunnel: kill $TUNNEL_PID"
echo "======================================================"
