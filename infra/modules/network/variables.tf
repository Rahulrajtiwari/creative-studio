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

# -----------------------------------------------------------------------------
# Required project / region inputs
# -----------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "GCP project that hosts the network resources (and downstream GKE / Cloud SQL when not Shared VPC)."
}

variable "region" {
  type        = string
  description = "Primary region for regional resources (subnets, Cloud SQL, GKE)."
}

variable "environment" {
  type        = string
  description = "Logical environment name used as a prefix/suffix for created resources (dev, qat, prd)."
  validation {
    condition     = contains(["dev", "qat", "prd", "development", "production", "staging", "test"], var.environment)
    error_message = "environment must be one of: dev, qat, prd, development, production, staging, test."
  }
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix; final names are \"$${name_prefix}-<resource>-$${environment}\"."
  default     = "cs"
}

# -----------------------------------------------------------------------------
# BYO toggles (leave blank to create fresh; provide self_link / name to reuse).
# Every BYO field has a matching create-mode field below so we never silently
# pick a CIDR that conflicts with anything existing.
# -----------------------------------------------------------------------------
variable "existing_vpc_self_link" {
  type        = string
  description = "Self-link of an existing VPC to reuse. Leave empty to create a new VPC."
  default     = ""
}

variable "existing_vpc_host_project_id" {
  type        = string
  description = "Host project ID if reusing a Shared VPC; empty otherwise."
  default     = ""
}

variable "existing_nodes_subnet_self_link" {
  type        = string
  description = "Self-link of an existing subnet to use for GKE nodes. Must already have pods + services secondary ranges."
  default     = ""
}

variable "existing_pods_secondary_range_name" {
  type        = string
  description = "Name of the existing pods secondary range on the BYO nodes subnet."
  default     = ""
}

variable "existing_services_secondary_range_name" {
  type        = string
  description = "Name of the existing services secondary range on the BYO nodes subnet."
  default     = ""
}

variable "existing_proxy_only_subnet_self_link" {
  type        = string
  description = "Self-link of an existing PROXY_ONLY subnet (REGIONAL_MANAGED_PROXY) for the L7 ILB. Leave empty to create."
  default     = ""
}

variable "existing_psc_subnet_self_link" {
  type        = string
  description = "Self-link of an existing subnet for the Private Service Connect endpoint. Leave empty to create."
  default     = ""
}

variable "existing_psa_range_name" {
  type        = string
  description = "Name of an existing global address used for Private Services Access (Cloud SQL peering). Leave empty to create."
  default     = ""
}

variable "existing_router_name" {
  type        = string
  description = "Name of an existing Cloud Router. Leave empty to create."
  default     = ""
}

variable "existing_dns_zone_name" {
  type        = string
  description = "Name of an existing private Cloud DNS zone for googleapis.com. Leave empty to create."
  default     = ""
}

# -----------------------------------------------------------------------------
# Create-mode inputs (always required, even if you also provide the matching
# existing_* — used for resource naming, validation, downstream firewalls, etc.)
# -----------------------------------------------------------------------------
variable "vpc_name" {
  type        = string
  description = "Name for the new VPC (only used when creating). Must be DNS-compliant."
}

variable "nodes_subnet_name" {
  type        = string
  description = "Name for the new nodes subnet (only used when creating)."
}

variable "nodes_cidr" {
  type        = string
  description = "Primary CIDR for the GKE nodes subnet (e.g. 10.20.0.0/22). Must NOT overlap with anything in disallowed_cidrs."
  validation {
    condition     = can(cidrnetmask(var.nodes_cidr))
    error_message = "nodes_cidr must be a valid CIDR (e.g. 10.20.0.0/22)."
  }
}

variable "pods_cidr" {
  type        = string
  description = "Secondary range for GKE pods on the nodes subnet (e.g. 10.21.0.0/16)."
  validation {
    condition     = can(cidrnetmask(var.pods_cidr))
    error_message = "pods_cidr must be a valid CIDR."
  }
}

variable "services_cidr" {
  type        = string
  description = "Secondary range for GKE services on the nodes subnet (e.g. 10.22.0.0/20)."
  validation {
    condition     = can(cidrnetmask(var.services_cidr))
    error_message = "services_cidr must be a valid CIDR."
  }
}

variable "proxy_only_subnet_name" {
  type        = string
  description = "Name for the proxy-only subnet (REGIONAL_MANAGED_PROXY) used by the L7 ILB."
}

variable "proxy_only_subnet_cidr" {
  type        = string
  description = "CIDR for the proxy-only subnet. /23 minimum recommended (e.g. 10.23.0.0/23)."
  validation {
    condition     = can(cidrnetmask(var.proxy_only_subnet_cidr)) && tonumber(split("/", var.proxy_only_subnet_cidr)[1]) <= 26
    error_message = "proxy_only_subnet_cidr must be a valid CIDR with prefix length /26 or larger (e.g. /23)."
  }
}

variable "psc_subnet_name" {
  type        = string
  description = "Name for the subnet that will host the PSC consumer endpoint(s)."
}

variable "psc_subnet_cidr" {
  type        = string
  description = "CIDR for the PSC subnet. Small range is fine (e.g. /28)."
  validation {
    condition     = can(cidrnetmask(var.psc_subnet_cidr))
    error_message = "psc_subnet_cidr must be a valid CIDR."
  }
}

variable "psc_googleapis_ip" {
  type        = string
  description = "Static IP (must lie within psc_subnet_cidr) reserved for the PSC endpoint that fronts *.googleapis.com."
}

variable "psa_range_name" {
  type        = string
  description = "Name for the Private Services Access (PSA) global address used by Cloud SQL VPC peering."
}

variable "psa_range_cidr" {
  type        = string
  description = "CIDR for the PSA range. Recommended /16 to give Google services room (e.g. 10.24.0.0/16)."
  validation {
    condition     = can(cidrnetmask(var.psa_range_cidr))
    error_message = "psa_range_cidr must be a valid CIDR."
  }
}

variable "router_name" {
  type        = string
  description = "Cloud Router name."
}

variable "dns_zone_name" {
  type        = string
  description = "Private DNS managed zone resource name (Terraform name)."
}

variable "dns_googleapis_zone_dns_name" {
  type        = string
  description = "DNS name for the private googleapis zone (must end with a dot, e.g. \"googleapis.com.\")."
  default     = "googleapis.com."
}

# -----------------------------------------------------------------------------
# Egress / firewall posture
# -----------------------------------------------------------------------------
variable "enable_nat" {
  type        = bool
  description = "Whether to provision Cloud NAT for egress (needed if pods must reach the IdP JWKS endpoint or any other public service that is not on PSC)."
  default     = true
}

variable "nat_name" {
  type        = string
  description = "Cloud NAT name (used only when enable_nat=true)."
  default     = ""
}

variable "nat_static_ip_count" {
  type        = number
  description = "Number of static external IPs to reserve for Cloud NAT (so the corporate IdP can allowlist them). Set to 0 for auto-allocate."
  default     = 1
  validation {
    condition     = var.nat_static_ip_count >= 0 && var.nat_static_ip_count <= 8
    error_message = "nat_static_ip_count must be 0..8."
  }
}

variable "master_authorized_cidrs" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "Corporate / VDI / bastion CIDRs allowed to reach the GKE control plane via VPC peering. PASSED THROUGH for downstream gke-private module to consume."
  default     = []
}

variable "disallowed_cidrs" {
  type        = list(string)
  description = "Existing on-prem / peered CIDRs that the create-mode CIDRs must NOT overlap with. Used for guardrail validation."
  default     = []
}

# -----------------------------------------------------------------------------
# Tags / labels
# -----------------------------------------------------------------------------
variable "labels" {
  type        = map(string)
  description = "Common labels applied to network resources that support labels."
  default     = {}
}
