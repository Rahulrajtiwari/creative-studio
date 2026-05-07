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

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google      = { source = "hashicorp/google", version = ">= 5.30, < 7.0" }
    google-beta = { source = "hashicorp/google-beta", version = ">= 5.30, < 7.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each           = toset(var.apis_to_enable)
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

module "platform" {
  source = "../../modules/platform-gke"

  project_id  = var.project_id
  region      = var.region
  environment = "prd"
  name_prefix = var.name_prefix
  labels      = var.labels

  network           = var.network
  gke               = var.gke
  cloudsql          = var.cloudsql
  gcs               = var.gcs
  artifact_registry = var.artifact_registry
  lb_config         = var.lb_config
  app               = var.app

  depends_on = [google_project_service.apis]
}

resource "local_file" "helm_values" {
  filename        = "${path.module}/generated/values-from-tf.yaml"
  content         = yamlencode(module.platform.helm_values)
  file_permission = "0644"
}
