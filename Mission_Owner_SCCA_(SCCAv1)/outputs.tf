# ###################################################################################################### #
# Copyright (c) 2023 Oracle and/or its affiliates, All rights reserved.                                  #
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl. #
# ###################################################################################################### #

output "bastion_ocid" {
  value = module.bastion.bastion_ocid
}

output "policy_to_add" {
  value = <<EOT
  The remote buckets should be created in the same region as SCCA LZ created.
  Please also add below policy to the root level of the remote tenancy:
  define tenancy SCCA-LZ-Tenancy as ${var.remote_tenancy_ocid},
  admit any-user of tenancy SCCA-LZ-Tenancy to manage object-family in tenancy
  EOT
}
output "idcs_endpoint" {
  value = module.identity_domain[0].domain.url
}

output "vdms_compartment_name" {
  value = module.vdms_compartment[0].compartment_name
}

output "home_compartment_id" {
  value = module.home_compartment[0].compartment_id
}

output "drg_id" {
  value = module.drg.drg_id
}

output "identity_domain_name" {
  value = module.identity_domain[0].name
}

output "key_ocid" {
  value = module.master_encryption_key.key_ocid
}
# Additional outputs for OKE deployment
# Add these to the existing outputs.tf in Mission_Owner_SCCA_(SCCAv1)/

output "workload_compartment_id" {
  description = "OCID of the Workload compartment"
  value       = module.workload_compartment[0].compartment_id
}

output "workload_vcn_id" {
  description = "OCID of the Workload VCN"
  value       = module.workload_network.vcn_id
}

output "workload_subnet_id" {
  description = "OCID of the Workload subnet"
  value       = module.workload_network.subnets[local.workload_network.subnet_map["OCI-SCCA-LZ-Workload-SUB"].name]
}

output "vdss_lb_subnet_id" {
  description = "OCID of the VDSS LB subnet (SUB2)"
  value       = module.vdss_network.subnets[local.vdss_network.subnet_map["OCI-SCCA-LZ-VDSS-SUB2"].name]
}

