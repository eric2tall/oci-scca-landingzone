# Scripts

These scripts are intended for use in **OCI Cloud Shell only**, by **admin users only**. Most rely on Cloud Shell's pre-authenticated `oci` CLI session and auto-detect the tenancy OCID (via `OCI_CLI_TENANCY`, `~/.oci/config`, or a live `oci iam compartment list` call), so they are not meant to be run from a regular workstation without equivalent setup and permissions. A few scripts have this tenancy's OCID hardcoded rather than auto-detected; those are noted below.

## aliases.sh

Not a standalone script. Shell aliases and functions for Cloud Shell (quality-of-life shortcuts, git, kubectl, and Terraform/SCCA landing zone shortcuts like `scca`, `tf-init`, `tf-plan`, `tf-apply`). Sourced from `.bashrc`, not executed directly.

## .bashrc

Cloud Shell bash profile: blue prompt, vi command-line mode, sources `aliases.sh`, and adds a git-aware prompt showing the current repo and branch.

## check_credits_remaining.sh

Fetches subscription and commitment details for this tenancy's specific subscription via `oci osub-subscription`, saves the raw response to `subscription_detail_raw.json`, and prints the non-null fields. **No parameters** — tenancy and subscription OCID are hardcoded to this tenancy.

## check_fastconnect_errors.sh

Searches OCI audit events for FastConnect-related errors within a recent time window (default: last 8 hours). Takes no positional arguments; override the lookback window with the `HOURS_BACK` environment variable.

## check_oci_ad_limits.sh

Checks OCI service limits per Availability Domain against a curated list of expected values (compute shapes: `standard-e4-core-count`, `standard-e4-memory-count`, `standard-e5-core-count`). No parameters; tenancy OCID can be overridden via `TENANCY_OCID` environment variable if auto-detection fails.

## check_oci_budgets.sh

Lists all budgets configured on the tenancy. No parameters.

## check_oci_credits.sh

Also lists budgets configured on the tenancy (similar to `check_oci_budgets.sh`). No parameters.

## check_oci_limits.sh

Checks a curated list of OCI service limits flagged as "extreme" (limits set 20x or more above current usage) across multiple services (analytics, api-gateway, and others), comparing actual usage against them. No parameters; tenancy OCID can be overridden via `TENANCY_OCID`.

## check_oci_subscription.sh

Lists the subscription(s) assigned to this tenancy via `oci organizations assigned-subscription list`. No parameters.

## check_rpc_errors.sh

Searches OCI audit events for RPC-related errors within a recent time window (default: last 8 hours). Same pattern as `check_fastconnect_errors.sh`; override with `HOURS_BACK`.

## check_subscription_status.sh

Confirms OCI subscription status via CLI, mirroring Console > Billing > Subscriptions. Useful for checking whether a suspended subscription has been restored.

Parameters:
- `-c <compartment_ocid>` — compartment to check (defaults to tenancy root if not set)
- `-p <plan_number>` — billing plan number (defaults to a hardcoded plan number for this tenancy)

## fastconnect_limits.sh

Shows OCI service limits and current usage for FastConnect.

Parameters:
- `-c <compartment_ocid>` — compartment to check (default: tenancy root)
- `-a` — check all subscribed regions (default: current Cloud Shell region only)

## oci_admin_users.sh

Finds every IAM group with "admin" in the name (case-insensitive) and reports on membership. No parameters; tenancy OCID can be overridden via `TENANCY_OCID`.

## oci_limits.sh

Auto-detects every region this tenancy is subscribed to and reports on service limits across all of them. No parameters.

## oci_tenancy_inventory.sh

Builds a compartment-ID-to-name lookup and produces a readable inventory report across the tenancy. No parameters.

## top_resource_costs.sh

Reports resources with costs above a threshold for a given date range (defaults to the first of the current month through today). **Tenancy OCID is hardcoded to this tenancy.**

Parameters (positional, all optional — prompts interactively if omitted):
1. `threshold` — minimum cost to report (default: 10)
2. `start_date` — `YYYY-MM-DD` (default: first of current month)
3. `end_date` — `YYYY-MM-DD` (default: today)
