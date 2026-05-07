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

variable "project_id" {
  type        = string
  description = "Project that hosts the Cloud SQL instance."
}

variable "region" {
  type        = string
  description = "Region for the Cloud SQL instance."
}

variable "environment" {
  type        = string
  description = "Logical environment used in resource naming."
}

variable "name_prefix" {
  type        = string
  default     = "cs"
  description = "Resource name prefix."
}

variable "existing_instance_name" {
  type        = string
  default     = ""
  description = "Name of an existing Cloud SQL instance to reuse. If empty, a new instance will be created."
}

variable "vpc_self_link" {
  type        = string
  description = "Self-link of the VPC the instance peers into via PSA."
}

variable "psa_peering_id" {
  type        = string
  description = "Resource ID of the google_service_networking_connection from the network module. Used to make sure the peering exists before the instance is created."
}

variable "database_version" {
  type        = string
  description = "Cloud SQL Postgres version."
  default     = "POSTGRES_15"
  validation {
    condition     = startswith(var.database_version, "POSTGRES_")
    error_message = "database_version must be a POSTGRES_* version."
  }
}

variable "tier" {
  type        = string
  description = "Machine tier."
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  type        = string
  description = "REGIONAL (HA) or ZONAL."
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  type        = number
  description = "Initial disk size in GB."
  default     = 50
}

variable "disk_autoresize_limit_gb" {
  type        = number
  description = "Upper bound for disk autoresize."
  default     = 500
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Cloud SQL instance deletion protection."
}

variable "db_name" {
  type        = string
  description = "Name of the database created in the instance."
  default     = "creative_studio"
}

variable "db_user" {
  type        = string
  description = "Application database user (password authentication)."
  default     = "studio_user"
}

variable "db_password_secret_id" {
  type        = string
  description = "Name of a Secret Manager secret holding the password for db_user. Must already exist."
}

variable "iam_database_users" {
  type        = list(string)
  description = "Service account emails (or full IAM principals) granted IAM-based DB authentication. Recommended path for the backend pod."
  default     = []
}

variable "backups" {
  type = object({
    enabled                        = bool
    point_in_time_recovery_enabled = bool
    start_time                     = string
    transaction_log_retention_days = number
    retained_backups               = number
  })
  description = "Backup configuration."
  default = {
    enabled                        = true
    point_in_time_recovery_enabled = true
    start_time                     = "02:00"
    transaction_log_retention_days = 7
    retained_backups               = 14
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels for the instance."
  default     = {}
}
