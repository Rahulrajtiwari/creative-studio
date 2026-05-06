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
  description = "Project that hosts the Artifact Registry repo."
}

variable "location" {
  type        = string
  description = "Repository location (region)."
}

variable "repository_id" {
  type        = string
  description = "Repository ID (the AR \"name\")."
}

variable "environment" {
  type        = string
  description = "Logical environment used in the repo description."
}

variable "reader_members" {
  type        = list(string)
  description = "Principals granted roles/artifactregistry.reader (e.g. nodes SA, Argo CD SA)."
  default     = []
}

variable "writer_members" {
  type        = list(string)
  description = "Principals granted roles/artifactregistry.writer (e.g. CI service account)."
  default     = []
}

variable "labels" {
  type        = map(string)
  description = "Labels."
  default     = {}
}
