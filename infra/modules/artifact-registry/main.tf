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

resource "google_artifact_registry_repository" "this" {
  project                = var.project_id
  location               = var.location
  repository_id          = var.repository_id
  format                 = "DOCKER"
  description            = "Private Docker repo for ${var.repository_id} (Creative Studio ${var.environment})."
  cleanup_policy_dry_run = false
  labels                 = var.labels

  docker_config {
    immutable_tags = true
  }

  cleanup_policies {
    id     = "keep-recent-untagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each   = toset(var.reader_members)
  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.this.repository_id
  role       = "roles/artifactregistry.reader"
  member     = each.value
}

resource "google_artifact_registry_repository_iam_member" "writers" {
  for_each   = toset(var.writer_members)
  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.this.repository_id
  role       = "roles/artifactregistry.writer"
  member     = each.value
}
