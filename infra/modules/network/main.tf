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
# Selectors: create vs reuse for every BYO-able resource.
# Downstream modules consume the locals only - they do not care which path ran.
# -----------------------------------------------------------------------------
locals {
  create_vpc          = trimspace(var.existing_vpc_self_link) == ""
  create_nodes_subnet = trimspace(var.existing_nodes_subnet_self_link) == ""
  create_proxy_subnet = trimspace(var.existing_proxy_only_subnet_self_link) == ""
  create_psc_subnet   = trimspace(var.existing_psc_subnet_self_link) == ""
  create_psa_range    = trimspace(var.existing_psa_range_name) == ""
  create_router       = trimspace(var.existing_router_name) == ""
  create_dns_zone     = trimspace(var.existing_dns_zone_name) == ""

  network_host_project = trimspace(var.existing_vpc_host_project_id) != "" ? var.existing_vpc_host_project_id : var.project_id

  # Pre-compute names that are derived rather than required as inputs.
  computed_nat_name = trimspace(var.nat_name) != "" ? var.nat_name : "${var.name_prefix}-nat-${var.environment}"
}

# -----------------------------------------------------------------------------
# Pre-flight validation: catch the easy CIDR foot-guns at plan time.
# True CIDR-overlap detection is not reliably expressible in pure HCL; we
# instead reject exact duplicates here and document `disallowed_cidrs` as a
# list of network prefixes for the operator's own audit, surfaced via the
# `vpc_cidrs` output for review.
# -----------------------------------------------------------------------------
resource "terraform_data" "preflight_distinct_cidrs" {
  input = {
    nodes_cidr             = var.nodes_cidr
    pods_cidr              = var.pods_cidr
    services_cidr          = var.services_cidr
    proxy_only_subnet_cidr = var.proxy_only_subnet_cidr
    psc_subnet_cidr        = var.psc_subnet_cidr
    psa_range_cidr         = var.psa_range_cidr
  }

  lifecycle {
    precondition {
      condition = length(distinct([
        var.nodes_cidr,
        var.pods_cidr,
        var.services_cidr,
        var.proxy_only_subnet_cidr,
        var.psc_subnet_cidr,
        var.psa_range_cidr,
      ])) == 6
      error_message = "nodes_cidr, pods_cidr, services_cidr, proxy_only_subnet_cidr, psc_subnet_cidr, and psa_range_cidr must all be distinct."
    }

    precondition {
      condition     = !contains(var.disallowed_cidrs, var.nodes_cidr) && !contains(var.disallowed_cidrs, var.pods_cidr) && !contains(var.disallowed_cidrs, var.services_cidr) && !contains(var.disallowed_cidrs, var.proxy_only_subnet_cidr) && !contains(var.disallowed_cidrs, var.psc_subnet_cidr) && !contains(var.disallowed_cidrs, var.psa_range_cidr)
      error_message = "At least one create-mode CIDR exactly matches an entry in disallowed_cidrs. Pick a different range."
    }
  }
}

# -----------------------------------------------------------------------------
# VPC (create or read)
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  count                           = local.create_vpc ? 1 : 0
  name                            = var.vpc_name
  project                         = var.project_id
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
  mtu                             = 1460
}

data "google_compute_network" "byo_vpc" {
  count   = local.create_vpc ? 0 : 1
  name    = reverse(split("/", var.existing_vpc_self_link))[0]
  project = local.network_host_project
}

# -----------------------------------------------------------------------------
# Nodes subnet (create or read) with secondary ranges for pods and services
# -----------------------------------------------------------------------------
resource "google_compute_subnetwork" "nodes" {
  count                    = local.create_nodes_subnet ? 1 : 0
  name                     = var.nodes_subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = local.vpc_self_link
  ip_cidr_range            = var.nodes_cidr
  private_ip_google_access = true
  purpose                  = "PRIVATE"
  stack_type               = "IPV4_ONLY"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  secondary_ip_range {
    range_name    = "${var.nodes_subnet_name}-pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "${var.nodes_subnet_name}-services"
    ip_cidr_range = var.services_cidr
  }
}

data "google_compute_subnetwork" "byo_nodes" {
  count   = local.create_nodes_subnet ? 0 : 1
  name    = reverse(split("/", var.existing_nodes_subnet_self_link))[0]
  region  = var.region
  project = local.network_host_project
}

# -----------------------------------------------------------------------------
# Proxy-only subnet for the regional L7 Internal HTTPS Load Balancer
# -----------------------------------------------------------------------------
resource "google_compute_subnetwork" "proxy_only" {
  count         = local.create_proxy_subnet ? 1 : 0
  name          = var.proxy_only_subnet_name
  project       = var.project_id
  region        = var.region
  network       = local.vpc_self_link
  ip_cidr_range = var.proxy_only_subnet_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

data "google_compute_subnetwork" "byo_proxy_only" {
  count     = local.create_proxy_subnet ? 0 : 1
  self_link = var.existing_proxy_only_subnet_self_link
}

# -----------------------------------------------------------------------------
# PSC subnet + endpoint for *.googleapis.com (no public egress required for
# Vertex AI, GCS, IAM Credentials, Artifact Registry, etc.)
# -----------------------------------------------------------------------------
resource "google_compute_subnetwork" "psc" {
  count                    = local.create_psc_subnet ? 1 : 0
  name                     = var.psc_subnet_name
  project                  = var.project_id
  region                   = var.region
  network                  = local.vpc_self_link
  ip_cidr_range            = var.psc_subnet_cidr
  private_ip_google_access = true
  purpose                  = "PRIVATE"
}

data "google_compute_subnetwork" "byo_psc" {
  count     = local.create_psc_subnet ? 0 : 1
  self_link = var.existing_psc_subnet_self_link
}

resource "google_compute_address" "psc_googleapis" {
  name         = "${var.name_prefix}-psc-googleapis-${var.environment}"
  project      = var.project_id
  region       = var.region
  subnetwork   = local.psc_subnet_self_link
  address_type = "INTERNAL"
  address      = var.psc_googleapis_ip
  purpose      = "GCE_ENDPOINT"
}

# PSC forwarding rule is commented out because Cloud NAT provides egress to
# Google APIs. Re-enable if you want fully private API access without NAT.
# resource "google_compute_forwarding_rule" "psc_googleapis" {
#   name                    = "${var.name_prefix}-psc-googleapis-${var.environment}"
#   project                 = var.project_id
#   region                  = var.region
#   network                 = local.vpc_self_link
#   ip_address              = google_compute_address.psc_googleapis.id
#   load_balancing_scheme   = ""
#   target                  = "all-apis"
#   allow_psc_global_access = true
# }

# -----------------------------------------------------------------------------
# Private Services Access (PSA) global address + VPC peering for Cloud SQL.
# Cloud SQL with private IP requires this peering.
# -----------------------------------------------------------------------------
resource "google_compute_global_address" "psa" {
  count         = local.create_psa_range ? 1 : 0
  name          = var.psa_range_name
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = tonumber(split("/", var.psa_range_cidr)[1])
  address       = split("/", var.psa_range_cidr)[0]
  network       = local.vpc_self_link
}

data "google_compute_global_address" "byo_psa" {
  count   = local.create_psa_range ? 0 : 1
  name    = var.existing_psa_range_name
  project = local.network_host_project
}

resource "google_service_networking_connection" "psa" {
  network = local.vpc_self_link
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    local.create_psa_range ? google_compute_global_address.psa[0].name : data.google_compute_global_address.byo_psa[0].name,
  ]
  deletion_policy = "ABANDON"
}

# -----------------------------------------------------------------------------
# Cloud Router + Cloud NAT (optional, only for egress to the IdP JWKS endpoint
# or any other public dependency that is not reachable via PSC).
# -----------------------------------------------------------------------------
resource "google_compute_router" "router" {
  count   = var.enable_nat && local.create_router ? 1 : 0
  name    = var.router_name
  project = var.project_id
  region  = var.region
  network = local.vpc_self_link
}

data "google_compute_router" "byo_router" {
  count   = var.enable_nat && !local.create_router ? 1 : 0
  name    = var.existing_router_name
  network = local.vpc_self_link
  region  = var.region
  project = local.network_host_project
}

resource "google_compute_address" "nat" {
  count        = var.enable_nat ? var.nat_static_ip_count : 0
  name         = "${local.computed_nat_name}-ip-${count.index}"
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_nat ? 1 : 0
  name                               = local.computed_nat_name
  project                            = var.project_id
  region                             = var.region
  router                             = local.create_router ? google_compute_router.router[0].name : data.google_compute_router.byo_router[0].name
  nat_ip_allocate_option             = var.nat_static_ip_count > 0 ? "MANUAL_ONLY" : "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  nat_ips                            = [for ip in google_compute_address.nat : ip.self_link]

  subnetwork {
    name                    = local.nodes_subnet_self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]
    secondary_ip_range_names = [
      local.pods_secondary_range_name,
    ]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# Private DNS zones for *.googleapis.com / *.pkg.dev / *.gcr.io are commented
# out because Cloud NAT provides egress to Google APIs. Re-enable these along
# with the PSC forwarding rule above if you want fully private API access
# without NAT.
# -----------------------------------------------------------------------------
# resource "google_dns_managed_zone" "googleapis" {
#   count       = local.create_dns_zone ? 1 : 0
#   name        = var.dns_zone_name
#   project     = var.project_id
#   dns_name    = var.dns_googleapis_zone_dns_name
#   description = "Private resolution of googleapis.com to the PSC endpoint (no public egress)."
#   visibility  = "private"
#
#   private_visibility_config {
#     networks {
#       network_url = local.vpc_self_link
#     }
#   }
# }
#
# data "google_dns_managed_zone" "byo_googleapis" {
#   count   = local.create_dns_zone ? 0 : 1
#   name    = var.existing_dns_zone_name
#   project = local.network_host_project
# }
#
# resource "google_dns_record_set" "googleapis_a" {
#   count        = local.create_dns_zone ? 1 : 0
#   project      = var.project_id
#   managed_zone = google_dns_managed_zone.googleapis[0].name
#   name         = "googleapis.com."
#   type         = "A"
#   ttl          = 300
#   rrdatas      = [var.psc_googleapis_ip]
# }
#
# resource "google_dns_record_set" "googleapis_wildcard_cname" {
#   count        = local.create_dns_zone ? 1 : 0
#   project      = var.project_id
#   managed_zone = google_dns_managed_zone.googleapis[0].name
#   name         = "*.googleapis.com."
#   type         = "CNAME"
#   ttl          = 300
#   rrdatas      = ["googleapis.com."]
# }
#
# resource "google_dns_managed_zone" "pkg_dev" {
#   count       = local.create_dns_zone ? 1 : 0
#   name        = "${var.name_prefix}-pkg-dev-${var.environment}"
#   project     = var.project_id
#   dns_name    = "pkg.dev."
#   description = "Private resolution of *.pkg.dev to PSC."
#   visibility  = "private"
#
#   private_visibility_config {
#     networks {
#       network_url = local.vpc_self_link
#     }
#   }
# }
#
# resource "google_dns_record_set" "pkg_dev_a" {
#   count        = local.create_dns_zone ? 1 : 0
#   project      = var.project_id
#   managed_zone = google_dns_managed_zone.pkg_dev[0].name
#   name         = "pkg.dev."
#   type         = "A"
#   ttl          = 300
#   rrdatas      = [var.psc_googleapis_ip]
# }
#
# resource "google_dns_record_set" "pkg_dev_wildcard" {
#   count        = local.create_dns_zone ? 1 : 0
#   project      = var.project_id
#   managed_zone = google_dns_managed_zone.pkg_dev[0].name
#   name         = "*.pkg.dev."
#   type         = "CNAME"
#   ttl          = 300
#   rrdatas      = ["pkg.dev."]
# }

# -----------------------------------------------------------------------------
# Canonical local outputs (single source of truth, regardless of BYO vs create)
# -----------------------------------------------------------------------------
locals {
  vpc_self_link = local.create_vpc ? google_compute_network.vpc[0].self_link : data.google_compute_network.byo_vpc[0].self_link
  vpc_id        = local.create_vpc ? google_compute_network.vpc[0].id : data.google_compute_network.byo_vpc[0].id
  vpc_name      = local.create_vpc ? google_compute_network.vpc[0].name : data.google_compute_network.byo_vpc[0].name

  nodes_subnet_self_link = local.create_nodes_subnet ? google_compute_subnetwork.nodes[0].self_link : data.google_compute_subnetwork.byo_nodes[0].self_link
  nodes_subnet_name      = local.create_nodes_subnet ? google_compute_subnetwork.nodes[0].name : data.google_compute_subnetwork.byo_nodes[0].name

  pods_secondary_range_name     = local.create_nodes_subnet ? "${var.nodes_subnet_name}-pods" : var.existing_pods_secondary_range_name
  services_secondary_range_name = local.create_nodes_subnet ? "${var.nodes_subnet_name}-services" : var.existing_services_secondary_range_name

  proxy_only_subnet_self_link = local.create_proxy_subnet ? google_compute_subnetwork.proxy_only[0].self_link : data.google_compute_subnetwork.byo_proxy_only[0].self_link
  psc_subnet_self_link        = local.create_psc_subnet ? google_compute_subnetwork.psc[0].self_link : data.google_compute_subnetwork.byo_psc[0].self_link
}
