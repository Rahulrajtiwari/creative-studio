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
# Top-level wrapper module that wires together every component of the strictly
# private Creative Studio platform on GKE. Environment roots (dev/qat/prd) only
# need to instantiate this module and pass tfvars.
# -----------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Primary region."
}

variable "environment" {
  type        = string
  description = "Logical environment name: dev | qat | prd."
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
  default     = "cs"
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to all label-supporting resources."
  default     = {}
}

# -----------------------------------------------------------------------------
# Network: see modules/network/variables.tf for the full BYO + create-mode
# input matrix. Every input is forwarded.
# -----------------------------------------------------------------------------
variable "network" {
  type = object({
    # BYO toggles (empty string means "create new")
    existing_vpc_self_link                 = optional(string, "")
    existing_vpc_host_project_id           = optional(string, "")
    existing_nodes_subnet_self_link        = optional(string, "")
    existing_pods_secondary_range_name     = optional(string, "")
    existing_services_secondary_range_name = optional(string, "")
    existing_proxy_only_subnet_self_link   = optional(string, "")
    existing_psc_subnet_self_link          = optional(string, "")
    existing_psa_range_name                = optional(string, "")
    existing_router_name                   = optional(string, "")
    existing_dns_zone_name                 = optional(string, "")

    # Create-mode inputs (always required)
    vpc_name               = string
    nodes_subnet_name      = string
    nodes_cidr             = string
    pods_cidr              = string
    services_cidr          = string
    proxy_only_subnet_name = string
    proxy_only_subnet_cidr = string
    psc_subnet_name        = string
    psc_subnet_cidr        = string
    psc_googleapis_ip      = string
    psa_range_name         = string
    psa_range_cidr         = string
    router_name            = string
    dns_zone_name          = string

    # Egress + firewall
    enable_nat          = optional(bool, true)
    nat_name            = optional(string, "")
    nat_static_ip_count = optional(number, 1)
    master_authorized_cidrs = list(object({
      cidr_block   = string
      display_name = string
    }))
    disallowed_cidrs = optional(list(string), [])
  })
  description = "Network module inputs - see modules/network/variables.tf for the field-by-field documentation."
}

# -----------------------------------------------------------------------------
# GKE
# -----------------------------------------------------------------------------
variable "gke" {
  type = object({
    existing_cluster_name      = optional(string, "")
    existing_cluster_location  = optional(string, "")
    manage_node_pools_when_byo = optional(bool, false)

    cluster_name                = optional(string, "")
    master_cidr                 = string
    release_channel             = optional(string, "STABLE")
    enable_dataplane_v2         = optional(bool, true)
    enable_binary_authorization = optional(bool, false)
    enable_confidential_nodes   = optional(bool, false)
    enable_image_streaming      = optional(bool, true)
    deletion_protection         = optional(bool, true)
    maintenance_start_time      = optional(string, "03:00")
    node_service_account_email  = optional(string, "")

    system_pool = optional(object({
      machine_type    = string
      min_nodes       = number
      max_nodes       = number
      disk_type       = string
      disk_size_gb    = number
      spot            = bool
      max_surge       = number
      max_unavailable = number
      }), {
      machine_type    = "e2-standard-4"
      min_nodes       = 1
      max_nodes       = 3
      disk_type       = "pd-balanced"
      disk_size_gb    = 100
      spot            = false
      max_surge       = 1
      max_unavailable = 0
    })

    app_pool = optional(object({
      machine_type    = string
      min_nodes       = number
      max_nodes       = number
      disk_type       = string
      disk_size_gb    = number
      spot            = bool
      max_surge       = number
      max_unavailable = number
      }), {
      machine_type    = "n2-standard-4"
      min_nodes       = 2
      max_nodes       = 10
      disk_type       = "pd-balanced"
      disk_size_gb    = 200
      spot            = false
      max_surge       = 1
      max_unavailable = 0
    })
  })
  description = "GKE module inputs."
}

# -----------------------------------------------------------------------------
# Cloud SQL (private)
# -----------------------------------------------------------------------------
variable "cloudsql" {
  type = object({
    database_version         = optional(string, "POSTGRES_15")
    tier                     = optional(string, "db-custom-2-7680")
    availability_type        = optional(string, "REGIONAL")
    disk_size_gb             = optional(number, 50)
    disk_autoresize_limit_gb = optional(number, 500)
    deletion_protection      = optional(bool, true)
    db_name                  = optional(string, "creative_studio")
    db_user                  = optional(string, "studio_user")
    db_password_secret_id    = string
    existing_instance_name   = optional(string, "")
    backups = optional(object({
      enabled                        = bool
      point_in_time_recovery_enabled = bool
      start_time                     = string
      transaction_log_retention_days = number
      retained_backups               = number
      }), {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7
      retained_backups               = 14
    })
  })
  description = "Cloud SQL inputs."
}

# -----------------------------------------------------------------------------
# GCS bucket
# -----------------------------------------------------------------------------
variable "gcs" {
  type = object({
    bucket_name       = string
    location          = optional(string, "")
    storage_class     = optional(string, "STANDARD")
    cors_origins      = list(string)
    access_log_bucket = string
    enable_versioning = optional(bool, true)
  })
  description = "GCS bucket inputs."
}

# -----------------------------------------------------------------------------
# Artifact Registry
# -----------------------------------------------------------------------------
variable "artifact_registry" {
  type = object({
    repository_id = string
    location      = optional(string, "")
    extra_readers = optional(list(string), [])
    extra_writers = optional(list(string), [])
  })
  description = "Artifact Registry inputs."
}

# -----------------------------------------------------------------------------
# Internal LB cert (corporate PKI uploaded as regional SSL cert)
# -----------------------------------------------------------------------------
variable "lb_config" {
  type = object({
    certificate_name     = string
    cert_pem_secret_id   = string
    key_pem_secret_id    = string
    lb_static_ip_address = optional(string, "")
  })
  description = "Load Balancer config inputs."
}

# -----------------------------------------------------------------------------
# Application config injected into the Kubernetes ConfigMap (rendered into
# Helm/Kustomize values via the platform output).
# -----------------------------------------------------------------------------
variable "app" {
  type = object({
    namespace          = string
    fqdn               = string
    backend_image_tag  = optional(string, "latest")
    frontend_image_tag = optional(string, "latest")

    oidc = object({
      issuer                 = string
      audiences              = list(string)
      frontend_client_id     = string
      allowed_email_domains  = optional(list(string), [])
      allowed_groups_claim   = optional(string, "groups")
      allowed_groups         = optional(list(string), [])
      authorized_party       = optional(string, "")
      jwks_cache_ttl_seconds = optional(number, 3600)
      idp_display_name       = optional(string, "Corporate SSO")
    })

    backend_signing_sa_email = string
    workflows_executor_url   = optional(string, "")
  })
  description = "Application-layer config that the chart pulls in via outputs."
}
