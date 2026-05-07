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

locals {
  create_cluster = trimspace(var.existing_cluster_name) == ""
  computed_name = (
    local.create_cluster
    ? (trimspace(var.cluster_name) != "" ? var.cluster_name : "${var.name_prefix}-${var.environment}")
    : var.existing_cluster_name
  )
  manage_node_pool = local.create_cluster || var.manage_node_pools_when_byo
  create_node_sa   = trimspace(var.node_service_account_email) == ""
}

# -----------------------------------------------------------------------------
# Least-privilege node service account (only created if the operator did not
# pass an existing one). Workload-level permissions are NOT granted here -
# they belong on the per-workload GSAs that the workload-identity module
# creates.
# -----------------------------------------------------------------------------
resource "google_service_account" "nodes" {
  count        = local.create_node_sa ? 1 : 0
  project      = var.project_id
  account_id   = "${var.name_prefix}-gke-node-${var.environment}"
  display_name = "GKE node SA for ${local.computed_name}"
}

resource "google_project_iam_member" "node_logging" {
  count   = local.create_node_sa ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}

resource "google_project_iam_member" "node_monitoring_writer" {
  count   = local.create_node_sa ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  count   = local.create_node_sa ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  count   = local.create_node_sa ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}

locals {
  node_sa_email = local.create_node_sa ? google_service_account.nodes[0].email : var.node_service_account_email
}

# -----------------------------------------------------------------------------
# Private regional cluster
# -----------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  count                       = local.create_cluster ? 1 : 0
  name                        = local.computed_name
  project                     = var.project_id
  location                    = var.region
  network                     = var.vpc_self_link
  subnetwork                  = var.nodes_subnet_self_link
  deletion_protection         = var.deletion_protection
  enable_shielded_nodes       = true
  enable_intranode_visibility = true
  remove_default_node_pool    = true
  initial_node_count          = 1
  resource_labels             = var.labels
  datapath_provider           = var.enable_dataplane_v2 ? "ADVANCED_DATAPATH" : "LEGACY_DATAPATH"
  networking_mode             = "VPC_NATIVE"

  node_config {
    shielded_instance_config {
      enable_secure_boot          = var.enable_secure_boot
      enable_integrity_monitoring = true
    }
  }

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_cidr

    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  network_policy {
    enabled  = !var.enable_dataplane_v2
    provider = var.enable_dataplane_v2 ? "PROVIDER_UNSPECIFIED" : "CALICO"
  }

  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    network_policy_config { disabled = var.enable_dataplane_v2 }
    gcp_filestore_csi_driver_config { enabled = false }
    gcs_fuse_csi_driver_config { enabled = true }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  dns_config {
    cluster_dns       = "CLOUD_DNS"
    cluster_dns_scope = "CLUSTER_SCOPE"
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
      "STORAGE",
      "POD",
      "DEPLOYMENT",
      "STATEFULSET",
      "DAEMONSET",
      "HPA",
      "CADVISOR",
      "KUBELET",
    ]
    managed_prometheus { enabled = true }

    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = false
    }
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_ENTERPRISE"
  }

  cost_management_config {
    enabled = true
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  node_pool_defaults {
    node_config_defaults {
      gcfs_config { enabled = var.enable_image_streaming }
    }
  }

  lifecycle {
    ignore_changes = [
      # Node pools are managed as separate resources below.
      node_pool,
      initial_node_count,
    ]
  }
}

# Read-back data source if we're reusing an existing cluster.
data "google_container_cluster" "byo" {
  count    = local.create_cluster ? 0 : 1
  name     = var.existing_cluster_name
  location = var.existing_cluster_location
  project  = var.project_id
}

# -----------------------------------------------------------------------------
# Node pools
# -----------------------------------------------------------------------------
resource "google_container_node_pool" "system" {
  count    = local.manage_node_pool ? 1 : 0
  name     = "system-pool"
  project  = var.project_id
  location = var.region
  cluster  = local.computed_name

  initial_node_count = var.system_pool.min_nodes

  autoscaling {
    min_node_count = var.system_pool.min_nodes
    max_node_count = var.system_pool.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = var.system_pool.max_surge
    max_unavailable = var.system_pool.max_unavailable
    strategy        = "SURGE"
  }

  node_config {
    machine_type    = var.system_pool.machine_type
    disk_type       = var.system_pool.disk_type
    disk_size_gb    = var.system_pool.disk_size_gb
    image_type      = "COS_CONTAINERD"
    spot            = var.system_pool.spot
    service_account = local.node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = var.enable_secure_boot
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    confidential_nodes {
      enabled = var.enable_confidential_nodes
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    labels = merge(var.labels, {
      "creative-studio.io/pool" = "system"
    })

    taint {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "PREFER_NO_SCHEDULE"
    }

    gcfs_config {
      enabled = var.enable_image_streaming
    }
  }

  depends_on = [google_container_cluster.this]
}

resource "google_container_node_pool" "app" {
  count    = local.manage_node_pool ? 1 : 0
  name     = "app-pool"
  project  = var.project_id
  location = var.region
  cluster  = local.computed_name

  initial_node_count = var.app_pool.min_nodes

  autoscaling {
    min_node_count = var.app_pool.min_nodes
    max_node_count = var.app_pool.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = var.app_pool.max_surge
    max_unavailable = var.app_pool.max_unavailable
    strategy        = "SURGE"
  }

  node_config {
    machine_type    = var.app_pool.machine_type
    disk_type       = var.app_pool.disk_type
    disk_size_gb    = var.app_pool.disk_size_gb
    image_type      = "COS_CONTAINERD"
    spot            = var.app_pool.spot
    service_account = local.node_sa_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = var.enable_secure_boot
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    confidential_nodes {
      enabled = var.enable_confidential_nodes
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    labels = merge(var.labels, {
      "creative-studio.io/pool" = "app"
    })

    gcfs_config {
      enabled = var.enable_image_streaming
    }
  }

  depends_on = [google_container_cluster.this]
}
