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
  description = "Project."
}

variable "region" {
  type        = string
  description = "Region of the regional SSL certificate (must match the L7 ILB)."
}

variable "environment" {
  type        = string
  description = "Logical environment name."
}

variable "certificate_name" {
  type        = string
  description = "Name of the regional SSL certificate."
}

variable "cert_pem_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the PEM-encoded leaf + intermediate chain."
}

variable "key_pem_secret_id" {
  type        = string
  description = "Secret Manager secret ID containing the PEM-encoded private key."
}

variable "ilb_static_ip_address" {
  type        = string
  description = "Optional internal IP (must be inside the nodes subnet primary range) reserved for the ILB. Leave empty to let the Ingress controller allocate one."
  default     = ""
}

variable "nodes_subnet_self_link" {
  type        = string
  description = "Self-link of the subnet from which to allocate the static internal IP (only used when ilb_static_ip_address is set)."
  default     = ""
}
