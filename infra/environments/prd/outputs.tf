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
  value = module.platform.cluster_name
}

output "cluster_location" {
  value = module.platform.cluster_location
}

output "vpc_self_link" {
  value = module.platform.vpc_self_link
}

output "psc_googleapis_ip" {
  value = module.platform.psc_googleapis_ip
}

output "cloudsql_connection_name" {
  value = module.platform.cloudsql_connection_name
}

output "cloudsql_private_ip" {
  value = module.platform.cloudsql_private_ip
}

output "gcs_bucket_name" {
  value = module.platform.gcs_bucket_name
}

output "artifact_registry_url" {
  value = module.platform.artifact_registry_url
}

output "ilb_certificate_name" {
  value = module.platform.ilb_certificate_name
}

output "ilb_static_ip_address" {
  value = module.platform.ilb_static_ip_address
}

output "backend_gsa_email" {
  value = module.platform.backend_gsa_email
}

output "frontend_gsa_email" {
  value = module.platform.frontend_gsa_email
}

output "helm_values_file" {
  value = local_file.helm_values.filename
}
