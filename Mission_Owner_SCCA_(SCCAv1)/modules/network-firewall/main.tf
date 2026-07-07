# ###################################################################################################### #
# Copyright (c) 2023 Oracle and/or its affiliates, All rights reserved.                                  #
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl. #
# ###################################################################################################### #

# New-style NFW module — uses separate policy sub-resources instead of inline blocks.
# Compatible with OCI provider 5.9.0+ without requiring manual Console policy upgrade.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ── POLICY SHELL ─────────────────────────────────────────────────────────────
resource "oci_network_firewall_network_firewall_policy" "network_firewall_policy" {
  display_name   = var.network_firewall_policy_name
  compartment_id = var.compartment_id
}

# ── ADDRESS LISTS ─────────────────────────────────────────────────────────────
resource "oci_network_firewall_network_firewall_policy_address_list" "address_lists" {
  for_each = var.ip_address_lists

  name                       = each.key
  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.network_firewall_policy.id
  type                       = "IP"
  addresses                  = each.value
}

# ── SECURITY RULES ────────────────────────────────────────────────────────────
resource "oci_network_firewall_network_firewall_policy_security_rule" "security_rules" {
  for_each = var.security_rules

  name                       = each.key
  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.network_firewall_policy.id
  action                     = each.value.security_rules_action

  condition {
    application = each.value.security_rules_condition_applications
    destination_address = each.value.security_rules_condition_destinations
    source_address      = each.value.security_rules_condition_sources
    url                 = each.value.security_rules_condition_urls
  }

  depends_on = [oci_network_firewall_network_firewall_policy_address_list.address_lists]
}

# ── FIREWALL INSTANCE ─────────────────────────────────────────────────────────
resource "oci_network_firewall_network_firewall" "network_firewall" {
  compartment_id             = var.compartment_id
  network_firewall_policy_id = oci_network_firewall_network_firewall_policy.network_firewall_policy.id
  subnet_id                  = var.network_firewall_subnet_id
  display_name               = var.network_firewall_name

  depends_on = [
    oci_network_firewall_network_firewall_policy.network_firewall_policy,
    oci_network_firewall_network_firewall_policy_security_rule.security_rules,
    oci_network_firewall_network_firewall_policy_address_list.address_lists,
  ]
}

resource "time_sleep" "network_firewall_ip_delay" {
  depends_on      = [oci_network_firewall_network_firewall.network_firewall]
  create_duration = "90s"
}
