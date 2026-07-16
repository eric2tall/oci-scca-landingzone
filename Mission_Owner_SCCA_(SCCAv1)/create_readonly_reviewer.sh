#!/usr/bin/env bash
set -euo pipefail

TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaamr5cziqjkuck3bsp2c3ktcx7imbszmwvvhvd454s6phpc5yl5xga"
HOME_COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaalvdomwjf3sd25onej2m76fsc7n3wxfup355tkp6itnj3n7vzrsdq"
GROUP_NAME="readonly-reviewers"
POLICY_NAME="readonly-reviewer-policy"

# Accept first.last as an argument, or prompt if not provided
if [ $# -ge 1 ]; then
  FIRST_LAST="$1"
else
  read -rp "Enter reviewer name as first.last: " FIRST_LAST
fi

# Basic validation: must look like first.last (letters/hyphens on each side)
if [[ ! "$FIRST_LAST" =~ ^[A-Za-z-]+\.[A-Za-z-]+$ ]]; then
  echo "Error: expected format first.last (e.g. kristofer.block)" >&2
  exit 1
fi

USER_NAME=$(echo "$FIRST_LAST" | tr '[:upper:]' '[:lower:]')
USER_EMAIL="${USER_NAME}@afs.com"

echo "Checking for existing user: $USER_NAME"
USER_OCID=$(oci iam user list \
  --compartment-id "$TENANCY_OCID" \
  --name "$USER_NAME" \
  --query "data[0].id" --raw-output 2>/dev/null || echo "null")

if [ "$USER_OCID" == "null" ] || [ -z "$USER_OCID" ]; then
  echo "  Not found, creating user: $USER_NAME"
  USER_OCID=$(oci iam user create \
    --compartment-id "$TENANCY_OCID" \
    --name "$USER_NAME" \
    --description "Read-only reviewer - SCCA landing zone demo" \
    --email "$USER_EMAIL" \
    --query "data.id" --raw-output)
else
  echo "  Found existing user, reusing"
fi
echo "  -> $USER_OCID"

echo "Checking for existing group: $GROUP_NAME"
GROUP_OCID=$(oci iam group list \
  --compartment-id "$TENANCY_OCID" \
  --name "$GROUP_NAME" \
  --query "data[0].id" --raw-output 2>/dev/null || echo "null")

if [ "$GROUP_OCID" == "null" ] || [ -z "$GROUP_OCID" ]; then
  echo "  Not found, creating group: $GROUP_NAME"
  GROUP_OCID=$(oci iam group create \
    --compartment-id "$TENANCY_OCID" \
    --name "$GROUP_NAME" \
    --description "Read-only access for SCCA landing zone review" \
    --query "data.id" --raw-output)
fi
echo "  -> $GROUP_OCID"

echo "Adding $USER_NAME to $GROUP_NAME"
set +e
ADD_OUTPUT=$(oci iam group add-user \
  --group-id "$GROUP_OCID" \
  --user-id "$USER_OCID" 2>&1)
ADD_STATUS=$?
set -e

if [ $ADD_STATUS -eq 0 ]; then
  echo "  -> done"
elif echo "$ADD_OUTPUT" | grep -qi "already a member\|duplicate"; then
  echo "  -> already a member, skipping"
else
  echo "  Warning: group add failed:"
  echo "$ADD_OUTPUT" | sed 's/^/    /'
fi

echo "Checking for existing policy: $POLICY_NAME"
POLICY_OCID=$(oci iam policy list \
  --compartment-id "$TENANCY_OCID" \
  --name "$POLICY_NAME" \
  --query "data[0].id" --raw-output 2>/dev/null || echo "null")

if [ "$POLICY_OCID" == "null" ] || [ -z "$POLICY_OCID" ]; then
  echo "  Not found, creating policy: $POLICY_NAME"
  POLICY_OCID=$(oci iam policy create \
    --compartment-id "$TENANCY_OCID" \
    --name "$POLICY_NAME" \
    --description "Read-only access to SCCA landing zone (Home compartment and children)" \
    --statements "[\"Allow group $GROUP_NAME to inspect all-resources in compartment id $HOME_COMPARTMENT_OCID\", \"Allow group $GROUP_NAME to read all-resources in compartment id $HOME_COMPARTMENT_OCID\"]" \
    --query "data.id" --raw-output)
fi
echo "  -> $POLICY_OCID"

echo "Triggering password reset for $USER_NAME"
set +e
PW_OUTPUT=$(oci iam user ui-password create-or-reset \
  --user-id "$USER_OCID" \
  --query "data.password" --raw-output 2>&1)
PW_STATUS=$?
set -e

if [ $PW_STATUS -eq 0 ] && [ -n "$PW_OUTPUT" ] && [ "$PW_OUTPUT" != "null" ]; then
  TEMP_PASSWORD="$PW_OUTPUT"
else
  TEMP_PASSWORD="(none returned - reset email sent instead, see note below)"
  if [ $PW_STATUS -ne 0 ]; then
    echo "  Warning: password reset call failed:"
    echo "$PW_OUTPUT" | sed 's/^/    /'
  fi
fi

echo ""
echo "=== Done ==="
echo "User OCID:     $USER_OCID"
echo "Group OCID:    $GROUP_OCID"
echo "Policy OCID:   $POLICY_OCID"
echo ""
echo "----------------------------------------"
echo "  Username: $USER_NAME"
echo "  Password: $TEMP_PASSWORD"
echo "----------------------------------------"
echo ""
echo "This tenancy uses Identity Domains: password reset typically sends"
echo "$USER_EMAIL a reset-link email rather than returning a plaintext"
echo "password here (though this tenancy has returned a password directly"
echo "in testing). Have $USER_NAME check that inbox (spam folder too) for"
echo "the activation link or password."
echo ""
echo "MFA: on first Console login, $USER_NAME will be prompted to enroll"
echo "in MFA via the Oracle Authenticator app (scan QR code or enter setup"
echo "key). This is an interactive step he must complete himself; the CLI"
echo "cannot do it on his behalf. Let him know ahead of time so he has the"
echo "app installed before logging in."
