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

resource "random_id" "suffix" {
  byte_length = 4
}

data "google_secret_manager_secret_version" "db_password" {
  count   = var.manage_db_and_users ? 1 : 0
  project = var.project_id
  secret  = var.db_password_secret_id
}

locals {
  create_instance = trimspace(var.existing_instance_name) == ""
  instance_name   = local.create_instance ? "${var.name_prefix}-pg-${var.environment}-${random_id.suffix.hex}" : var.existing_instance_name
}

data "google_sql_database_instance" "byo" {
  count   = local.create_instance ? 0 : 1
  name    = var.existing_instance_name
  project = var.project_id
}

resource "google_sql_database_instance" "this" {
  count               = local.create_instance ? 1 : 0
  name                = local.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    availability_type           = var.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_self_link
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    backup_configuration {
      enabled                        = var.backups.enabled
      point_in_time_recovery_enabled = var.backups.point_in_time_recovery_enabled
      start_time                     = var.backups.start_time
      transaction_log_retention_days = var.backups.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backups.retained_backups
        retention_unit   = "COUNT"
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
  }

  depends_on = [var.psa_peering_id]
}

resource "google_sql_database" "default" {
  count    = var.manage_db_and_users ? 1 : 0
  project  = var.project_id
  name     = var.db_name
  instance = local.instance_name
}

resource "google_sql_user" "app" {
  count           = var.manage_db_and_users ? 1 : 0
  project         = var.project_id
  name            = var.db_user
  instance        = local.instance_name
  password        = data.google_secret_manager_secret_version.db_password[0].secret_data
  deletion_policy = "ABANDON"
}

# IAM-based DB users (one per workload service account). The Cloud SQL Auth
# Proxy sidecar will request short-lived OAuth tokens via Workload Identity,
# so we can drop password auth entirely for the app over time.
resource "google_sql_user" "iam" {
  for_each        = var.manage_db_and_users ? toset(var.iam_database_users) : toset([])
  project         = var.project_id
  name            = replace(each.value, ".gserviceaccount.com", "")
  instance        = local.instance_name
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = "ABANDON"
}
