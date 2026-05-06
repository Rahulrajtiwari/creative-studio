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

output "certificate_name" {
  description = "Name of the regional SSL certificate (consumed by the Ingress annotation)."
  value       = google_compute_region_ssl_certificate.this.name
}

output "ilb_static_ip_name" {
  description = "Name of the reserved static internal IP for the ILB (empty if not reserved)."
  value       = length(google_compute_address.ilb) > 0 ? google_compute_address.ilb[0].name : ""
}

output "ilb_static_ip_address" {
  description = "Reserved static internal IP (empty if not reserved)."
  value       = length(google_compute_address.ilb) > 0 ? google_compute_address.ilb[0].address : ""
}
