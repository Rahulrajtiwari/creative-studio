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
# Per-workload Google service accounts + Workload Identity bindings to KSAs
# in the GKE cluster.
# -----------------------------------------------------------------------------

resource "google_service_account" "this" {
  for_each     = var.workloads
  project      = var.project_id
  account_id   = each.value.gsa_account_id
  display_name = "Workload SA for ${each.key} (${var.environment})"
  description  = "Bound via Workload Identity to KSA ${each.value.ksa_namespace}/${each.value.ksa_name}."
}

resource "google_service_account_iam_member" "wi_user" {
  for_each           = var.workloads
  service_account_id = google_service_account.this[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.ksa_namespace}/${each.value.ksa_name}]"
}

# Project-level role grants per workload.
locals {
  project_iam_pairs = flatten([
    for k, w in var.workloads : [
      for r in w.project_roles : {
        workload = k
        role     = r
      }
    ]
  ])
}

resource "google_project_iam_member" "workload" {
  for_each = {
    for p in local.project_iam_pairs : "${p.workload}|${p.role}" => p
  }
  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.this[each.value.workload].email}"
}

# Service-account-impersonation grants (e.g. signing for v4 GCS URLs).
locals {
  sa_impersonation_pairs = flatten([
    for k, w in var.workloads : [
      for sa in w.impersonation_targets : {
        workload    = k
        target_sa   = sa.target_service_account
        target_role = sa.role
      }
    ]
  ])
}

resource "google_service_account_iam_member" "impersonation" {
  for_each = {
    for p in local.sa_impersonation_pairs : "${p.workload}|${p.target_sa}|${p.target_role}" => p
  }
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.target_sa}"
  role               = each.value.target_role
  member             = "serviceAccount:${google_service_account.this[each.value.workload].email}"
}
