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
# Firewall posture for the strictly-private cluster.
# - Default-deny (egress) is achieved by NetworkPolicies inside the cluster
#   plus the absence of any 0.0.0.0/0 allow rule.
# - The rules below are the only ingress paths permitted into nodes:
#     1. Internal HTTPS LB health checks + proxies (proxy-only subnet)
#     2. Master to nodes for kubelet (10250), webhooks (8443/9443), and the
#        kube-apiserver TLS port (443). GKE auto-creates a similar rule for
#        new clusters, but we manage it explicitly so `kubectl exec`,
#        `kubectl logs`, `port-forward`, and admission webhooks don't silently
#        break if that auto-rule is ever deleted by an admin or org policy.
# - Egress rules are kept tight: only to PSC endpoint, to Cloud SQL PSA range,
#   intra-VPC, and (optionally) IdP CIDRs.
# -----------------------------------------------------------------------------

# Allow Google L7 ILB health-check + proxy traffic to reach pods on common ports.
resource "google_compute_firewall" "ingress_lb_health_checks" {
  name        = "${var.name_prefix}-allow-l7ilb-hc-${var.environment}"
  project     = var.project_id
  network     = local.vpc_self_link
  description = "Allow L7 ILB proxy + Google health-check ranges into pods."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [
    var.proxy_only_subnet_cidr,
    "130.211.0.0/22",
    "35.191.0.0/16",
  ]

  allow {
    protocol = "tcp"
    ports    = ["8080", "80", "443"]
  }
}

# Allow the GKE control plane (master CIDR) to reach kubelet + webhook ports
# on nodes. Required for `kubectl exec`, `kubectl logs`, `kubectl port-forward`,
# admission webhooks, and metrics scraping. Without this, those operations
# fail with i/o timeouts on TCP 10250.
resource "google_compute_firewall" "ingress_master_to_nodes" {
  name        = "${var.name_prefix}-allow-master-to-nodes-${var.environment}"
  project     = var.project_id
  network     = local.vpc_self_link
  description = "Allow GKE master CIDR to reach kubelet (10250), webhooks (8443/9443), and TLS (443) on nodes."
  direction   = "INGRESS"
  priority    = 990

  source_ranges = [var.master_cidr]

  allow {
    protocol = "tcp"
    ports    = ["443", "10250", "8443", "9443", "15017"]
  }
}

# Allow intra-VPC traffic between nodes/pods (kubelet, kube-proxy, DNS, etc.).
resource "google_compute_firewall" "ingress_intra_vpc" {
  name        = "${var.name_prefix}-allow-intra-vpc-${var.environment}"
  project     = var.project_id
  network     = local.vpc_self_link
  description = "Allow internal east-west traffic within the VPC and pod ranges."
  direction   = "INGRESS"
  priority    = 1100

  source_ranges = local.create_nodes_subnet ? compact([var.nodes_cidr, var.pods_cidr, var.services_cidr]) : concat([data.google_compute_subnetwork.byo_nodes[0].ip_cidr_range], [for r in data.google_compute_subnetwork.byo_nodes[0].secondary_ip_range : r.ip_cidr_range])

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# Explicit deny-all ingress fallback (highest priority number means evaluated
# last among denies; we only need it to make the posture explicit in audits).
resource "google_compute_firewall" "ingress_deny_all" {
  name        = "${var.name_prefix}-deny-all-ingress-${var.environment}"
  project     = var.project_id
  network     = local.vpc_self_link
  description = "Default-deny ingress fallback. Allow rules above this priority must be explicit."
  direction   = "INGRESS"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]

  deny { protocol = "all" }
}

# Egress: only to PSC endpoint, Cloud SQL PSA range, intra-VPC. Everything else
# is implicitly denied via the explicit egress deny rule below; if Cloud NAT is
# enabled the operator can add a higher-priority allow rule for IdP CIDRs.
resource "google_compute_firewall" "egress_to_psc_googleapis" {
  name      = "${var.name_prefix}-egress-psc-googleapis-${var.environment}"
  project   = var.project_id
  network   = local.vpc_self_link
  direction = "EGRESS"
  priority  = 900

  destination_ranges = ["${var.psc_googleapis_ip}/32"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "egress_to_cloudsql_psa" {
  name      = "${var.name_prefix}-egress-cloudsql-psa-${var.environment}"
  project   = var.project_id
  network   = local.vpc_self_link
  direction = "EGRESS"
  priority  = 910

  destination_ranges = [var.psa_range_cidr]

  allow {
    protocol = "tcp"
    ports    = ["3307", "5432"]
  }
}

resource "google_compute_firewall" "egress_intra_vpc" {
  name      = "${var.name_prefix}-egress-intra-vpc-${var.environment}"
  project   = var.project_id
  network   = local.vpc_self_link
  direction = "EGRESS"
  priority  = 920

  destination_ranges = compact([
    var.nodes_cidr,
    var.pods_cidr,
    var.services_cidr,
    var.proxy_only_subnet_cidr,
    var.psc_subnet_cidr,
    var.master_cidr,
  ])

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# Default-deny egress. Operators must add a higher-priority allow rule for any
# additional public destination (e.g. IdP CIDRs when Cloud NAT is enabled).
resource "google_compute_firewall" "egress_deny_all" {
  name      = "${var.name_prefix}-deny-all-egress-${var.environment}"
  project   = var.project_id
  network   = local.vpc_self_link
  direction = "EGRESS"
  priority  = 65534

  destination_ranges = ["0.0.0.0/0"]

  deny { protocol = "all" }
}
