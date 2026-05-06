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

# Reads the corporate-PKI cert + private key from Secret Manager (so the
# operator can rotate by overwriting the secret) and uploads them as a
# regional google_compute_region_ssl_certificate consumed by the Internal
# HTTPS Load Balancer that the GKE `gce-internal` Ingress provisions.
data "google_secret_manager_secret_version" "cert_pem" {
  project = var.project_id
  secret  = var.cert_pem_secret_id
}

data "google_secret_manager_secret_version" "key_pem" {
  project = var.project_id
  secret  = var.key_pem_secret_id
}

resource "google_compute_region_ssl_certificate" "this" {
  name        = var.certificate_name
  project     = var.project_id
  region      = var.region
  description = "Internal HTTPS LB cert for ${var.environment} (corp PKI)."
  certificate = data.google_secret_manager_secret_version.cert_pem.secret_data
  private_key = data.google_secret_manager_secret_version.key_pem.secret_data

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_address" "ilb" {
  count        = trimspace(var.ilb_static_ip_address) != "" ? 1 : 0
  name         = "${var.certificate_name}-ip"
  project      = var.project_id
  region       = var.region
  subnetwork   = var.nodes_subnet_self_link
  address_type = "INTERNAL"
  address      = var.ilb_static_ip_address
  purpose      = "GCE_ENDPOINT"
}
