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

output "vpc_self_link" {
  value = module.network.vpc_self_link
}

output "nodes_subnet_self_link" {
  value = module.network.nodes_subnet_self_link
}

output "psc_googleapis_ip" {
  value = module.network.psc_googleapis_ip
}

output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_location" {
  value = module.gke.cluster_location
}

output "cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "workload_identity_pool" {
  value = module.gke.workload_identity_pool
}

output "cloudsql_connection_name" {
  value = module.cloudsql.connection_name
}

output "cloudsql_private_ip" {
  value = module.cloudsql.private_ip_address
}

output "cloudsql_database_name" {
  value = module.cloudsql.database_name
}

output "cloudsql_database_user" {
  value = module.cloudsql.database_user
}

output "gcs_bucket_name" {
  value = module.gcs.name
}

output "artifact_registry_url" {
  value = module.artifact_registry.repository_url
}

output "lb_certificate_name" {
  value = module.ssl_cert.certificate_name
}

output "lb_static_ip_address" {
  value = module.ssl_cert.lb_static_ip_address
}

output "backend_gsa_email" {
  description = "Google service account email bound to the backend KSA via Workload Identity."
  value       = google_service_account.placeholder_for_iam_user.email
}

output "frontend_gsa_email" {
  description = "Google service account email bound to the frontend KSA via Workload Identity."
  value       = lookup(module.workload_identity.service_account_emails, "frontend", "")
}

# -----------------------------------------------------------------------------
# Helm values that the deploy/helm/creative-studio chart consumes.
#
# The shape exactly matches the chart's values.yaml schema, so an environment
# root can render this directly into `generated/values-from-tf.yaml` and pass
# it to `helm upgrade -f values-from-tf.yaml -f values-<env>.yaml ...`.
# -----------------------------------------------------------------------------
output "helm_values" {
  description = "Helm values derived from the Terraform-managed infrastructure."
  value = {
    global = {
      projectId   = var.project_id
      region      = var.region
      environment = var.environment
      appHost     = var.app.fqdn
    }

    image = {
      registry = module.artifact_registry.repository_url
    }

    backend = {
      serviceAccount = {
        create               = true
        googleServiceAccount = google_service_account.placeholder_for_iam_user.email
      }
      config = {
        PROJECT_ID             = var.project_id
        LOCATION               = var.region
        FRONTEND_URL           = "https://${var.app.fqdn}"
        BACKEND_URL            = "https://${var.app.fqdn}"
        WORKFLOWS_EXECUTOR_URL = trimspace(var.app.workflows_executor_url) != "" ? var.app.workflows_executor_url : "https://${var.app.fqdn}/api/workflows-executor"
        DB_HOST                = "127.0.0.1"
        DB_PORT                = "5432"
        DB_NAME                = var.cloudsql.db_name
        # With cloudSqlProxy.iamAuthn=true (the default), the proxy authenticates
        # using the GSA's OAuth token AND the DB user must be the GSA email with
        # the ".gserviceaccount.com" suffix stripped. Cloud SQL creates this IAM
        # DB user via google_sql_user.iam in the cloudsql-private module.
        DB_USER                  = trimsuffix(google_service_account.placeholder_for_iam_user.email, ".gserviceaccount.com")
        USE_CLOUD_SQL_AUTH_PROXY = "true"
        GENMEDIA_BUCKET             = module.gcs.name
        VIDEO_BUCKET                = module.gcs.name
        IMAGE_BUCKET                = module.gcs.name
        OIDC_ISSUER                 = var.app.oidc.issuer
        OIDC_AUDIENCES              = join(",", var.app.oidc.audiences)
        OIDC_ALLOWED_EMAIL_DOMAINS  = join(",", var.app.oidc.allowed_email_domains)
        OIDC_ALLOWED_GROUPS_CLAIM   = var.app.oidc.allowed_groups_claim
        OIDC_ALLOWED_GROUPS         = join(",", var.app.oidc.allowed_groups)
        OIDC_AUTHORIZED_PARTY       = var.app.oidc.authorized_party
        OIDC_REQUIRE_EMAIL_VERIFIED = "true"
        JWKS_CACHE_TTL_SEC          = tostring(var.app.oidc.jwks_cache_ttl_seconds)
        BEHIND_INGRESS              = "true"
        TRUSTED_HOSTS               = var.app.fqdn

        # Service account used by IamSignerCredentials to mint v4-signed
        # download URLs for GCS objects returned by /api/gallery/* and
        # other media endpoints. Without it set, the signer silently
        # returns raw `gs://` URIs which browsers can't render. We reuse
        # the backend GSA (self-impersonation) because it already has:
        #   - `roles/iam.serviceAccountTokenCreator` at the project level
        #     (granted in platform-gke/main.tf:215-219) which permits the
        #     backend to call iamcredentials.sign_blob on itself.
        #   - `roles/storage.objectAdmin` on the bucket (granted via
        #     module.gcs.object_admin_members in this file) which covers
        #     the storage.objects.get permission that v4 signing requires.
        # No additional IAM bindings are needed.
        SIGNING_SA_EMAIL = google_service_account.placeholder_for_iam_user.email
      }
    }

    frontend = {
      serviceAccount = {
        create               = true
        googleServiceAccount = lookup(module.workload_identity.service_account_emails, "frontend", "")
      }
      config = {
        BACKEND_SERVICE_PORT  = "8080"
        OIDC_AUTHORITY        = var.app.oidc.issuer
        OIDC_CLIENT_ID        = var.app.oidc.frontend_client_id
        OIDC_AUDIENCE         = length(var.app.oidc.audiences) > 0 ? var.app.oidc.audiences[0] : ""
        OIDC_SCOPE            = "openid profile email"
        OIDC_IDP_DISPLAY_NAME = var.app.oidc.idp_display_name
      }
    }

    cloudSqlProxy = {
      instanceConnectionName = module.cloudsql.connection_name
    }

    ingress = {
      preSharedCertName = module.ssl_cert.certificate_name
      staticIpName      = module.ssl_cert.lb_static_ip_name
      hosts = [
        {
          host = var.app.fqdn
          paths = [
            { path = "/api", pathType = "Prefix", serviceName = "backend" },
            { path = "/", pathType = "Prefix", serviceName = "frontend" },
          ]
        },
      ]
    }

    networkPolicies = {
      egress = {
        cloudSqlPsaCidrs = [var.network.psa_range_cidr]
      }
    }

    # External Secrets mapping. With Cloud SQL IAM auth (the default), the
    # backend authenticates via the proxy's OAuth token and DB_PASS is
    # ignored, so this mapping is harmless. It is required when an operator
    # disables iamAuthn (e.g. BYO Cloud SQL without IAM auth) so the backend
    # can fetch the password from Secret Manager via the External Secrets
    # Operator. The ESO ClusterSecretStore must use Workload Identity bound
    # to a GSA with roles/secretmanager.secretAccessor on db_password_secret_id.
    externalSecrets = {
      enabled = true
      data = {
        DB_PASS = var.cloudsql.db_password_secret_id
      }
    }
  }
}
