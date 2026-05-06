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

resource "google_storage_bucket" "this" {
  name                        = var.bucket_name
  project                     = var.project_id
  location                    = var.location
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  storage_class               = var.storage_class

  versioning {
    enabled = var.enable_versioning
  }

  # CORS is restricted to the internal corporate origin(s) only - no wildcard.
  # Presigned URL uploads from the Angular SPA still work because the SPA is
  # served from the same private origin.
  dynamic "cors" {
    for_each = length(var.cors_origins) > 0 ? [1] : []
    content {
      origin          = var.cors_origins
      method          = ["GET", "PUT", "POST", "HEAD", "OPTIONS"]
      response_header = ["Content-Type", "x-goog-resumable", "Authorization", "Origin"]
      max_age_seconds = 3600
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action_type
        storage_class = lookup(lifecycle_rule.value, "storage_class", null)
      }
      condition {
        age                = lookup(lifecycle_rule.value, "age", null)
        with_state         = lookup(lifecycle_rule.value, "with_state", null)
        num_newer_versions = lookup(lifecycle_rule.value, "num_newer_versions", null)
      }
    }
  }

  logging {
    log_bucket = var.access_log_bucket
  }

  labels = var.labels
}

# Workload Identity bound IAM bindings.
resource "google_storage_bucket_iam_member" "object_admin" {
  for_each = toset(var.object_admin_members)
  bucket   = google_storage_bucket.this.name
  role     = "roles/storage.objectAdmin"
  member   = each.value
}

resource "google_storage_bucket_iam_member" "object_viewer" {
  for_each = toset(var.object_viewer_members)
  bucket   = google_storage_bucket.this.name
  role     = "roles/storage.objectViewer"
  member   = each.value
}
