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

output "cluster_name" {
  description = "Name of the cluster (created or BYO)."
  value       = local.computed_name
}

output "cluster_location" {
  description = "Region of the cluster."
  value       = local.create_cluster ? google_container_cluster.this[0].location : data.google_container_cluster.byo[0].location
}

output "cluster_endpoint" {
  description = "Private control-plane endpoint."
  value       = local.create_cluster ? google_container_cluster.this[0].private_cluster_config[0].private_endpoint : data.google_container_cluster.byo[0].private_cluster_config[0].private_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA cert."
  sensitive   = true
  value       = local.create_cluster ? google_container_cluster.this[0].master_auth[0].cluster_ca_certificate : data.google_container_cluster.byo[0].master_auth[0].cluster_ca_certificate
}

output "workload_identity_pool" {
  description = "Workload Identity pool URI for IAM bindings."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Service account email used by node pools."
  value       = local.node_sa_email
}
