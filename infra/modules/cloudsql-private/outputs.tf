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

output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = local.instance_name
}

output "connection_name" {
  description = "INSTANCE_CONNECTION_NAME used by the Cloud SQL Auth Proxy."
  value       = local.create_instance ? google_sql_database_instance.this[0].connection_name : data.google_sql_database_instance.byo[0].connection_name
}

output "private_ip_address" {
  description = "Private IP allocated to the instance via PSA."
  value       = local.create_instance ? google_sql_database_instance.this[0].private_ip_address : data.google_sql_database_instance.byo[0].private_ip_address
}

output "database_name" {
  description = "Name of the application database."
  value       = google_sql_database.default.name
}

output "database_user" {
  description = "Password-auth application user."
  value       = google_sql_user.app.name
}
