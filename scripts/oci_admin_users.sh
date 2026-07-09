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
  echo "  TENANCY_OCID=ocid1.tenancy.oc1..xxxx ./oci_admin_users.sh" >&2
  exit 1
fi
echo "Tenancy OCID: $TENANCY_OCID"
echo

# --- Find every group with "admin" in the name (case-insensitive) ---
echo "Looking up groups with 'admin' in the name..."
mapfile -t ADMIN_GROUPS < <(oci iam group list \
  --compartment-id "$TENANCY_OCID" \
  --all \
  --query "data[?contains(name,'Admin') || contains(name,'admin') || contains(name,'ADMIN')].{id:id,name:name}" \
| jq -c '.[]')

if [[ ${#ADMIN_GROUPS[@]} -eq 0 ]]; then
  echo "No groups with 'admin' in the name were found."
  exit 0
fi

echo "Found ${#ADMIN_GROUPS[@]} admin-like group(s):"
for g in "${ADMIN_GROUPS[@]}"; do
  echo "  - $(jq -r '.name' <<<"$g")"
done
echo

OUT="oci_admin_users.csv"
echo "group_name,user_name,user_id" > "$OUT"
TOTAL=0
GROUP_IDX=0

for g in "${ADMIN_GROUPS[@]}"; do
  GROUP_IDX=$((GROUP_IDX + 1))
  GID=$(jq -r '.id' <<<"$g")
  GNAME=$(jq -r '.name' <<<"$g")
  echo "=== Group [$GROUP_IDX/${#ADMIN_GROUPS[@]}]: $GNAME ==="

  MEMBERS_JSON=$(oci iam group list-users --group-id "$GID" --all \
    | jq -c '.data[] | {name: .name, id: .id}')

  if [[ -z "$MEMBERS_JSON" ]]; then
    echo "  no members"
    echo
    continue
  fi

  COUNT=0
  while IFS= read -r m; do
    UNAME=$(jq -r '.name' <<<"$m")
    UOCID=$(jq -r '.id' <<<"$m")
    echo "  - $UNAME"
    jq -rn --arg g "$GNAME" --arg n "$UNAME" --arg i "$UOCID" '[$g,$n,$i] | @csv' >> "$OUT"
    COUNT=$((COUNT + 1))
  done <<< "$MEMBERS_JSON"

  TOTAL=$((TOTAL + COUNT))
  echo "  -> $COUNT member(s)"
  echo
done

echo "Done: $OUT ($TOTAL admin membership row(s) across ${#ADMIN_GROUPS[@]} group(s))"
echo
echo "Note: this only covers classic IAM groups (the Default identity domain)."
echo "If this tenancy has additional identity domains with their own admin"
echo "groups, those aren't covered here and would need the identity-domains API."
