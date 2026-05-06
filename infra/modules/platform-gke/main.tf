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
# Network (always evaluated; module decides BYO vs create internally)
# -----------------------------------------------------------------------------
module "network" {
  source = "../network"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  name_prefix = var.name_prefix
  labels      = var.labels

  existing_vpc_self_link                 = var.network.existing_vpc_self_link
  existing_vpc_host_project_id           = var.network.existing_vpc_host_project_id
  existing_nodes_subnet_self_link        = var.network.existing_nodes_subnet_self_link
  existing_pods_secondary_range_name     = var.network.existing_pods_secondary_range_name
  existing_services_secondary_range_name = var.network.existing_services_secondary_range_name
  existing_proxy_only_subnet_self_link   = var.network.existing_proxy_only_subnet_self_link
  existing_psc_subnet_self_link          = var.network.existing_psc_subnet_self_link
  existing_psa_range_name                = var.network.existing_psa_range_name
  existing_router_name                   = var.network.existing_router_name
  existing_dns_zone_name                 = var.network.existing_dns_zone_name

  vpc_name               = var.network.vpc_name
  nodes_subnet_name      = var.network.nodes_subnet_name
  nodes_cidr             = var.network.nodes_cidr
  pods_cidr              = var.network.pods_cidr
  services_cidr          = var.network.services_cidr
  proxy_only_subnet_name = var.network.proxy_only_subnet_name
  proxy_only_subnet_cidr = var.network.proxy_only_subnet_cidr
  psc_subnet_name        = var.network.psc_subnet_name
  psc_subnet_cidr        = var.network.psc_subnet_cidr
  psc_googleapis_ip      = var.network.psc_googleapis_ip
  psa_range_name         = var.network.psa_range_name
  psa_range_cidr         = var.network.psa_range_cidr
  router_name            = var.network.router_name
  dns_zone_name          = var.network.dns_zone_name

  enable_nat              = var.network.enable_nat
  nat_name                = var.network.nat_name
  nat_static_ip_count     = var.network.nat_static_ip_count
  master_authorized_cidrs = var.network.master_authorized_cidrs
  disallowed_cidrs        = var.network.disallowed_cidrs
}

# -----------------------------------------------------------------------------
# GKE private cluster
# -----------------------------------------------------------------------------
module "gke" {
  source = "../gke-private"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  name_prefix = var.name_prefix
  labels      = var.labels

  vpc_self_link                 = module.network.vpc_self_link
  nodes_subnet_self_link        = module.network.nodes_subnet_self_link
  pods_secondary_range_name     = module.network.pods_secondary_range_name
  services_secondary_range_name = module.network.services_secondary_range_name

  master_cidr             = var.gke.master_cidr
  master_authorized_cidrs = var.network.master_authorized_cidrs

  existing_cluster_name      = var.gke.existing_cluster_name
  existing_cluster_location  = var.gke.existing_cluster_location
  manage_node_pools_when_byo = var.gke.manage_node_pools_when_byo

  cluster_name                = var.gke.cluster_name
  release_channel             = var.gke.release_channel
  enable_dataplane_v2         = var.gke.enable_dataplane_v2
  enable_binary_authorization = var.gke.enable_binary_authorization
  enable_confidential_nodes   = var.gke.enable_confidential_nodes
  enable_image_streaming      = var.gke.enable_image_streaming
  deletion_protection         = var.gke.deletion_protection
  maintenance_start_time      = var.gke.maintenance_start_time
  node_service_account_email  = var.gke.node_service_account_email

  system_pool = var.gke.system_pool
  app_pool    = var.gke.app_pool
}

# -----------------------------------------------------------------------------
# Cloud SQL (private IP via PSA)
# -----------------------------------------------------------------------------
module "cloudsql" {
  source = "../cloudsql-private"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  name_prefix = var.name_prefix
  labels      = var.labels

  vpc_self_link  = module.network.vpc_self_link
  psa_peering_id = module.network.psa_peering_id

  database_version         = var.cloudsql.database_version
  tier                     = var.cloudsql.tier
  availability_type        = var.cloudsql.availability_type
  disk_size_gb             = var.cloudsql.disk_size_gb
  disk_autoresize_limit_gb = var.cloudsql.disk_autoresize_limit_gb
  deletion_protection      = var.cloudsql.deletion_protection
  db_name                  = var.cloudsql.db_name
  db_user                  = var.cloudsql.db_user
  db_password_secret_id    = var.cloudsql.db_password_secret_id
  backups                  = var.cloudsql.backups

  iam_database_users = [
    google_service_account.placeholder_for_iam_user.email,
  ]
}

# Placeholder GSA used so we can grant Cloud SQL IAM auth to the eventual
# backend SA *before* the workload-identity module is applied. The real
# binding to the backend KSA happens in workload-identity below; this avoids a
# chicken-and-egg cycle in `terraform apply` ordering.
resource "google_service_account" "placeholder_for_iam_user" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-be-${var.environment}"
  display_name = "Backend workload SA - bound to KSA via Workload Identity"
  description  = "Cloud SQL IAM auth + Vertex/GCS access for the FastAPI backend pods."
}

# -----------------------------------------------------------------------------
# GCS bucket
# -----------------------------------------------------------------------------
module "gcs" {
  source = "../gcs-private"

  project_id            = var.project_id
  bucket_name           = var.gcs.bucket_name
  location              = trimspace(var.gcs.location) != "" ? var.gcs.location : var.region
  storage_class         = var.gcs.storage_class
  cors_origins          = var.gcs.cors_origins
  enable_versioning     = var.gcs.enable_versioning
  access_log_bucket     = var.gcs.access_log_bucket
  labels                = var.labels
  object_admin_members  = ["serviceAccount:${google_service_account.placeholder_for_iam_user.email}"]
  object_viewer_members = []
}

# -----------------------------------------------------------------------------
# Artifact Registry (private)
# -----------------------------------------------------------------------------
module "artifact_registry" {
  source = "../artifact-registry"

  project_id    = var.project_id
  location      = trimspace(var.artifact_registry.location) != "" ? var.artifact_registry.location : var.region
  repository_id = var.artifact_registry.repository_id
  environment   = var.environment
  labels        = var.labels

  reader_members = concat(
    ["serviceAccount:${module.gke.node_service_account_email}"],
    var.artifact_registry.extra_readers,
  )
  writer_members = var.artifact_registry.extra_writers
}

# -----------------------------------------------------------------------------
# Internal LB SSL cert from corporate PKI
# -----------------------------------------------------------------------------
module "ilb_cert" {
  source = "../internal-lb-cert"

  project_id             = var.project_id
  region                 = var.region
  environment            = var.environment
  certificate_name       = var.ilb_cert.certificate_name
  cert_pem_secret_id     = var.ilb_cert.cert_pem_secret_id
  key_pem_secret_id      = var.ilb_cert.key_pem_secret_id
  ilb_static_ip_address  = var.ilb_cert.ilb_static_ip_address
  nodes_subnet_self_link = module.network.nodes_subnet_self_link
}

# -----------------------------------------------------------------------------
# Workload Identity bindings (backend + frontend)
# -----------------------------------------------------------------------------
module "workload_identity" {
  source = "../workload-identity"

  project_id  = var.project_id
  environment = var.environment

  workloads = {
    backend = {
      gsa_account_id = google_service_account.placeholder_for_iam_user.account_id
      ksa_namespace  = var.app.namespace
      ksa_name       = "cs-backend-ksa"
      project_roles = [
        "roles/aiplatform.user",
        "roles/cloudsql.client",
        "roles/cloudsql.instanceUser",
        "roles/secretmanager.secretAccessor",
        "roles/iam.serviceAccountTokenCreator",
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
      ]
      impersonation_targets = []
    }
    frontend = {
      gsa_account_id = "${var.name_prefix}-fe-${var.environment}"
      ksa_namespace  = var.app.namespace
      ksa_name       = "cs-frontend-ksa"
      project_roles = [
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
      ]
      impersonation_targets = []
    }
  }
}

# Override: bind the backend KSA to the *placeholder* GSA we already created
# so it can be used as a Cloud SQL IAM user. We keep the placeholder GSA as
# the authoritative backend SA; the WI module only manages the frontend SA
# afresh. To avoid duplicate management, declare the WI binding directly
# here for the placeholder.
resource "google_service_account_iam_member" "backend_wi_binding" {
  service_account_id = google_service_account.placeholder_for_iam_user.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.app.namespace}/cs-backend-ksa]"
}
