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
  description = "Project that owns the Google service accounts."
}

variable "environment" {
  type        = string
  description = "Logical environment, used in display names."
}

variable "workloads" {
  type = map(object({
    gsa_account_id = string
    ksa_namespace  = string
    ksa_name       = string
    project_roles  = list(string)
    impersonation_targets = list(object({
      target_service_account = string
      role                   = string
    }))
  }))
  description = <<-EOT
    Map of workload name -> Workload Identity binding spec. Example:

    workloads = {
      backend = {
        gsa_account_id        = "cs-backend-prd"
        ksa_namespace         = "creative-studio"
        ksa_name              = "cs-backend-ksa"
        project_roles         = ["roles/aiplatform.user", "roles/cloudsql.client", "roles/cloudsql.instanceUser", "roles/secretmanager.secretAccessor"]
        impersonation_targets = []
      }
    }
  EOT
  default     = {}
}
