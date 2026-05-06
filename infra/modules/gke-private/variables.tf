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
  description = "Project that hosts the GKE cluster."
}

variable "region" {
  type        = string
  description = "Region of the regional GKE cluster."
}

variable "environment" {
  type        = string
  description = "Logical environment (dev, qat, prd) used in resource names."
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix; final cluster name is \"$${name_prefix}-$${environment}\" unless cluster_name is set."
  default     = "cs"
}

variable "cluster_name" {
  type        = string
  description = "Cluster name. If empty the module derives \"$${name_prefix}-$${environment}\"."
  default     = ""
}

# -----------------------------------------------------------------------------
# Network plumbing (consumed from the network module's outputs)
# -----------------------------------------------------------------------------
variable "vpc_self_link" {
  type        = string
  description = "Self-link of the VPC the cluster lives in."
}

variable "nodes_subnet_self_link" {
  type        = string
  description = "Self-link of the nodes subnet."
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Name of the pods secondary range on the nodes subnet."
}

variable "services_secondary_range_name" {
  type        = string
  description = "Name of the services secondary range on the nodes subnet."
}

variable "master_cidr" {
  type        = string
  description = "Internal /28 CIDR for the GKE control plane (e.g. 172.16.0.0/28). Must be unique across peerings."
  validation {
    condition     = can(cidrnetmask(var.master_cidr)) && tonumber(split("/", var.master_cidr)[1]) == 28
    error_message = "master_cidr must be a valid /28 CIDR."
  }
}

variable "master_authorized_cidrs" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "List of corporate / VDI / bastion CIDRs allowed to reach the private control plane endpoint."
}

# -----------------------------------------------------------------------------
# BYO toggle: reuse an existing private GKE cluster instead of creating one.
# When existing_cluster_id is set the module *only* creates node pools (if
# manage_node_pools_when_byo=true) and skips cluster creation entirely.
# -----------------------------------------------------------------------------
variable "existing_cluster_name" {
  type        = string
  description = "Name of an existing private GKE cluster to reuse. Leave empty to create."
  default     = ""
}

variable "existing_cluster_location" {
  type        = string
  description = "Location of the existing GKE cluster (region for regional clusters)."
  default     = ""
}

variable "manage_node_pools_when_byo" {
  type        = bool
  description = "Whether to manage node pools when an existing cluster is reused. Default false: assume the existing cluster already has node pools."
  default     = false
}

# -----------------------------------------------------------------------------
# Cluster configuration
# -----------------------------------------------------------------------------
variable "release_channel" {
  type        = string
  description = "GKE release channel."
  default     = "STABLE"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE."
  }
}

variable "enable_dataplane_v2" {
  type        = bool
  description = "Enable GKE Dataplane V2 (Cilium-based) for richer NetworkPolicy support."
  default     = true
}

variable "enable_binary_authorization" {
  type        = bool
  description = "Enable Binary Authorization (PROJECT_SINGLETON_POLICY_ENFORCE)."
  default     = false
}

variable "enable_confidential_nodes" {
  type        = bool
  description = "Use Confidential VMs for nodes (AMD SEV)."
  default     = false
}

variable "enable_image_streaming" {
  type        = bool
  description = "Use image streaming to pull from Artifact Registry."
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "Cluster-level deletion protection."
  default     = true
}

variable "maintenance_start_time" {
  type        = string
  description = "Daily maintenance window start time in HH:MM (UTC)."
  default     = "03:00"
}

variable "labels" {
  type        = map(string)
  description = "Labels for the cluster."
  default     = {}
}

# -----------------------------------------------------------------------------
# Node pools
# -----------------------------------------------------------------------------
variable "system_pool" {
  type = object({
    machine_type    = string
    min_nodes       = number
    max_nodes       = number
    disk_type       = string
    disk_size_gb    = number
    spot            = bool
    max_surge       = number
    max_unavailable = number
  })
  description = "Configuration for the system node pool that runs cluster add-ons."
  default = {
    machine_type    = "e2-standard-4"
    min_nodes       = 1
    max_nodes       = 3
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    spot            = false
    max_surge       = 1
    max_unavailable = 0
  }
}

variable "app_pool" {
  type = object({
    machine_type    = string
    min_nodes       = number
    max_nodes       = number
    disk_type       = string
    disk_size_gb    = number
    spot            = bool
    max_surge       = number
    max_unavailable = number
  })
  description = "Configuration for the application node pool that runs Creative Studio workloads."
  default = {
    machine_type    = "n2-standard-4"
    min_nodes       = 2
    max_nodes       = 10
    disk_type       = "pd-balanced"
    disk_size_gb    = 200
    spot            = false
    max_surge       = 1
    max_unavailable = 0
  }
}

variable "node_service_account_email" {
  type        = string
  description = "Email of an existing service account to attach to nodes. Leave empty to let the module create a least-privilege node SA."
  default     = ""
}
