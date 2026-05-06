# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

output "vpc_self_link" {
  description = "Self-link of the VPC (created or BYO)."
  value       = local.vpc_self_link
}

output "vpc_id" {
  description = "Resource ID of the VPC (created or BYO)."
  value       = local.vpc_id
}

output "vpc_name" {
  description = "Name of the VPC (created or BYO)."
  value       = local.vpc_name
}

output "network_host_project_id" {
  description = "Project that owns the VPC (host project for Shared VPC, or service project for non-shared)."
  value       = local.network_host_project
}

output "nodes_subnet_self_link" {
  description = "Self-link of the GKE nodes subnet."
  value       = local.nodes_subnet_self_link
}

output "nodes_subnet_name" {
  description = "Name of the GKE nodes subnet."
  value       = local.nodes_subnet_name
}

output "pods_secondary_range_name" {
  description = "Name of the secondary range used for GKE pods on the nodes subnet."
  value       = local.pods_secondary_range_name
}

output "services_secondary_range_name" {
  description = "Name of the secondary range used for GKE services on the nodes subnet."
  value       = local.services_secondary_range_name
}

output "proxy_only_subnet_self_link" {
  description = "Self-link of the proxy-only subnet used by the L7 ILB."
  value       = local.proxy_only_subnet_self_link
}

output "psc_subnet_self_link" {
  description = "Self-link of the PSC subnet."
  value       = local.psc_subnet_self_link
}

output "psc_googleapis_ip" {
  description = "Internal IP that fronts *.googleapis.com via Private Service Connect."
  value       = google_compute_address.psc_googleapis.address
}

output "psa_peering_id" {
  description = "ID of the service networking connection (PSA) used by Cloud SQL."
  value       = google_service_networking_connection.psa.id
}

output "nat_external_ips" {
  description = "External IPs reserved for Cloud NAT (empty if NAT is disabled or auto-allocated)."
  value       = [for ip in google_compute_address.nat : ip.address]
}

output "master_authorized_cidrs" {
  description = "Pass-through of the corp/VDI CIDRs that should be allowed to reach the GKE control plane."
  value       = var.master_authorized_cidrs
}

output "vpc_cidrs" {
  description = "Convenience map of every CIDR managed by this module (handy for downstream NetworkPolicies)."
  value = {
    nodes      = var.nodes_cidr
    pods       = var.pods_cidr
    services   = var.services_cidr
    proxy_only = var.proxy_only_subnet_cidr
    psc        = var.psc_subnet_cidr
    psa        = var.psa_range_cidr
  }
}
