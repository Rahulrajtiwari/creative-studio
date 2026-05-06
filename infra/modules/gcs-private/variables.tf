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
  description = "Project that owns the bucket."
}

variable "bucket_name" {
  type        = string
  description = "Globally-unique bucket name."
}

variable "location" {
  type        = string
  description = "Bucket location (e.g. us-central1 or US)."
}

variable "storage_class" {
  type        = string
  description = "Storage class."
  default     = "STANDARD"
}

variable "enable_versioning" {
  type        = bool
  description = "Enable object versioning."
  default     = true
}

variable "cors_origins" {
  type        = list(string)
  description = "Allowed CORS origins. MUST be the internal corporate hostname(s) (e.g. https://creative-studio.corp.example.com). Empty list disables CORS."
  default     = []
  validation {
    condition     = !contains(var.cors_origins, "*")
    error_message = "Wildcard CORS (\"*\") is not permitted on private buckets. List the corporate hostnames explicitly."
  }
}

variable "lifecycle_rules" {
  type        = list(map(any))
  description = "Optional list of lifecycle rule maps."
  default     = []
}

variable "access_log_bucket" {
  type        = string
  description = "Bucket to which access logs are delivered."
}

variable "object_admin_members" {
  type        = list(string)
  description = "Principals (formatted as e.g. serviceAccount:foo@bar.iam) granted roles/storage.objectAdmin."
  default     = []
}

variable "object_viewer_members" {
  type        = list(string)
  description = "Principals granted roles/storage.objectViewer."
  default     = []
}

variable "labels" {
  type        = map(string)
  description = "Labels."
  default     = {}
}
