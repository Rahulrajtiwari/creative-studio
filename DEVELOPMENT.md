# Development & Operations Guide — Creative Studio (Private GKE)

This guide covers the day-to-day developer workflow on a laptop, the
Terraform / Helm deployment lifecycle for **dev / qat / prd** clusters, and
the most common operational runbooks (rotating an OIDC client, scaling,
incident response).

The application is intentionally only reachable from corporate networks
(VDI / VPN / Cloud Interconnect / sanctioned proxy). The Firebase Hosting
and Cloud Run flow has been replaced by an Internal HTTPS Load Balancer +
private GKE cluster. Bootstrap.sh is no longer the supported path.

---

## 1. Prerequisites

| Tool                                | Min version | Notes                                                   |
|-------------------------------------|-------------|---------------------------------------------------------|
| `gcloud`                            | latest      | Configure `gcloud auth application-default login`        |
| `docker` + `docker compose`         | 24.x        | Used for the local stack                                |
| `node` (via `nvm`)                  | 20.x        | Frontend build                                          |
| `uv`                                | latest      | Python dependency manager                               |
| `terraform`                         | 1.6+        | For `infra/environments/<env>`                          |
| `helm`                              | 3.13+       | Required for `helm template` / `helm upgrade --install` |
| `kustomize`                         | 5+          | Optional; needs `--enable-helm`                         |
| `kubectl`                           | matches GKE | `gke-gcloud-auth-plugin` is required                    |

---

## 2. Local development (Docker Compose)

### 2.1 Backend `backend/.local.env`

The repo ships a working `.local.env` for `docker-compose.yml`. The minimum
you need to override before first run:

```bash
PROJECT_ID="my-dev-project"
GENMEDIA_BUCKET="my-dev-genmedia"
VIDEO_BUCKET="my-dev-video"
IMAGE_BUCKET="my-dev-image"

# Local Postgres container (already wired in docker-compose.yml)
DB_USER="studio_user"
DB_PASS="studio_pass"
DB_NAME="creative_studio"
DB_HOST="postgres"
DB_PORT="5432"
USE_CLOUD_SQL_AUTH_PROXY=false

# OIDC — point to a dev IdP (or run a local Keycloak in docker-compose).
OIDC_ISSUER="https://login.example.com/idp"
OIDC_AUDIENCES="creative-studio-dev"
OIDC_ALLOWED_EMAIL_DOMAINS="example.com"

# Cross-origin (Angular dev server runs on 4200; Nginx proxies in prod)
BEHIND_INGRESS=false
TRUSTED_HOSTS="localhost,127.0.0.1"
```

> **Heads-up**: there is **no `isLocal=true` shortcut** anymore. Both backend
> and frontend exclusively use OIDC + JWT. For local development you can
> point at the same dev IdP your team uses, or stand up a local Keycloak
> instance and add it to `OIDC_ISSUER`.

### 2.2 Frontend runtime config

`frontend/src/assets/runtime-config.json` is generated at container start
from `runtime-config.template.json` by `docker-entrypoint.sh`. For
`ng serve` development, `frontend/src/environments/environment.development.ts`
is consumed directly. Edit it to point at your local backend and IdP:

```ts
export const environment = {
  production: false,
  isLocal: true,
  backendURL: '/api',
  oidc: {
    authority: 'https://login.example.com/idp',
    clientId: 'creative-studio-dev',
    scope: 'openid profile email',
    audience: 'creative-studio-dev',
    idpDisplayName: 'Corporate SSO (Dev)',
  },
};
```

`proxy.conf.json` proxies `/api` to the backend container (`backend:8080`).

### 2.3 Spin it up

```bash
gcloud auth application-default login
gcloud config set project $PROJECT_ID

docker compose up
```

Seed templates the first time:

```bash
docker exec -t creative-studio-backend \
  sh -c "PYTHONPATH=/app uv run python -m bootstrap.bootstrap"
```

---

## 3. Production deployment lifecycle

### 3.1 Provision (Terraform)

```bash
cd infra/environments/dev          # or qat / prd
cp dev.tfvars.example dev.tfvars   # fill in CIDRs, OIDC IDs, hostnames
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

The `platform-gke` wrapper module emits a `helm_values_yaml` output that
the env root writes to `values-from-tf.yaml`. Use it alongside the
in-repo `values-<env>.yaml` to override anything the platform decides at
provision time (image registry path, GSA emails, internal IP names, etc.):

```bash
helm upgrade --install creative-studio deploy/helm/creative-studio \
  -n creative-studio --create-namespace --atomic --timeout 15m \
  -f deploy/helm/creative-studio/values-dev.yaml \
  -f infra/environments/dev/values-from-tf.yaml \
  --set backend.image.tag=$BACKEND_TAG \
  --set frontend.image.tag=$FRONTEND_TAG \
  --set migrations.image.tag=$BACKEND_TAG
```

### 3.2 Build & push images (Cloud Build)

The pipelines under `deploy/cloudbuild/` run on a **private worker pool**:

```bash
gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-backend.yaml \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool

gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-frontend.yaml \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool
```

Each pipeline writes a `*-image-pinned.txt` artifact with the digest
reference; downstream Helm commands and Argo CD bumps **must** consume
the digest, not the SHA tag, in production.

### 3.3 GitOps with Argo CD

1. Apply `deploy/argocd/project.yaml` and `deploy/argocd/applicationset.yaml`
   to the management cluster (Argo CD itself must also be on a private LB).
2. The CI image-bumper updates `deploy/helm/creative-studio/values-<env>.yaml`
   with the new pinned digest and commits.
3. Argo CD auto-syncs the change within ~30s; rollout health is reflected
   in the Argo UI and surfaced via the Helm chart's `NOTES.txt`.

### 3.4 BYO matrix

| Resource                       | Variable to reuse existing                          | Required even when reusing                                          |
|--------------------------------|-----------------------------------------------------|----------------------------------------------------------------------|
| VPC                            | `network.existing_vpc_name`                         | `network.gke_subnet_cidr`, secondary CIDRs                          |
| GKE primary subnet             | `network.existing_gke_subnet_name`                  | Pods/Services secondary range names + CIDRs                          |
| Proxy-only subnet              | `network.existing_proxy_only_subnet_name`           | `network.proxy_only_subnet_cidr`                                    |
| GKE cluster                    | `gke.existing_cluster_name`                         | Master CIDR, node-pool sizing, Workload Identity pool name          |
| Cloud SQL                      | `cloudsql.existing_instance_name`                   | PSA range CIDR, IAM-auth admin GSA                                  |
| GCS buckets                    | `gcs.existing_bucket_name_*`                        | UBLA-on, public-access prevention, scoped CORS origins              |

If a variable is left blank, Terraform creates the resource. If supplied,
the module falls back to `data` lookups but still requires CIDR-ranges so
ops can validate non-overlapping IP allocation.

---

## 4. Operations runbook

### 4.1 Health checks

```bash
# Liveness (fast, no DB / IdP touch)
kubectl -n creative-studio exec deploy/creative-studio-backend -c app -- \
  wget -qO- http://localhost:8080/healthz

# Readiness (verifies DB + OIDC discovery)
kubectl -n creative-studio exec deploy/creative-studio-backend -c app -- \
  wget -qO- http://localhost:8080/readyz
```

The frontend Nginx exposes `/healthz` and `/readyz` for the same purpose.

### 4.2 Tail logs

```bash
kubectl -n creative-studio logs deploy/creative-studio-backend -c app -f
kubectl -n creative-studio logs deploy/creative-studio-backend -c cloud-sql-proxy -f
kubectl -n creative-studio logs deploy/creative-studio-frontend -c nginx -f
```

### 4.3 Force a re-pull / rollout restart

```bash
kubectl -n creative-studio rollout restart deploy/creative-studio-backend
kubectl -n creative-studio rollout status  deploy/creative-studio-backend
```

### 4.4 Inspect database state

```bash
kubectl -n creative-studio exec -it deploy/creative-studio-backend -c app -- \
  psql -h 127.0.0.1 -U $(yq '.backend.config.DB_USER' values-prd.yaml) \
       -d $(yq '.backend.config.DB_NAME' values-prd.yaml)
```

### 4.5 Rotate the OIDC client

1. Issue a new `client_secret` (or new keypair for `private_key_jwt`) in the IdP.
2. Update the Secret Manager secret consumed by ESO (`gcp-secret-manager`).
3. Force-refresh the External Secret:
   ```bash
   kubectl -n creative-studio annotate externalsecret \
     creative-studio-backend-secrets \
     force-sync=$(date +%s) --overwrite
   ```
4. Roll the backend Deployment so pods pick up the rotated secret.

### 4.6 Onboarding a new IdP

| Setting                       | Value to ask the IdP team for                                          |
|-------------------------------|-------------------------------------------------------------------------|
| Client type                   | Public client (PKCE) for the SPA, or confidential w/ `private_key_jwt` |
| Allowed callback              | `https://<corp-host>/`                                                  |
| Allowed logout                | `https://<corp-host>/login`                                             |
| Required scopes               | `openid profile email` (+ `offline_access` if refresh tokens needed)    |
| Required claims               | `email`, `email_verified`, `groups`                                     |
| Token signing alg             | `RS256` (or `ES256`) — verifier supports both                           |

Then update the env's `*.tfvars` (`OIDC_ISSUER`, `OIDC_AUDIENCES`,
`OIDC_ALLOWED_GROUPS`) and `values-<env>.yaml` (`oidc.authority`,
`oidc.clientId`, `oidc.audience`, `oidc.idpDisplayName`).

### 4.7 Capacity / scaling

- **Backend**: HPA is already configured on CPU + memory.
  Bump `autoscaling.maxReplicas` and the GKE node pool's `max_node_count`
  in tandem when needed.
- **Cloud SQL**: enable `cloudsql.high_availability` (regional HA) and
  consider read replicas for analytic workloads.
- **Vertex AI quotas**: track per-region request quotas; the backend
  surfaces 429s as user-visible rate-limit errors.

### 4.8 Incident response (top-level checklist)

1. `kubectl get events -n creative-studio --sort-by=.lastTimestamp | tail`
2. Tail backend, cloud-sql-proxy, and Cilium/Dataplane V2 logs.
3. Check the Internal LB's backend health in Cloud Console (URL map ->
   backend service -> NEG endpoints).
4. Check `kubectl -n creative-studio get networkpolicies` — a recently
   deployed policy can blackhole egress.
5. If everything else is healthy, verify the OIDC IdP is reachable from the
   cluster nodes (PSC route to `googleapis.com` is a common culprit).

---

## 5. Code quality & pre-commit

The pre-commit pipeline is unchanged. Run it via Docker:

```bash
cp pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
docker compose run --rm pre-commit run --all-files
```

| Tool          | Scope                  |
|---------------|------------------------|
| `black`       | Backend formatting     |
| `pylint`      | Backend linting (>=9.0)|
| `pytest-cov`  | Backend tests (>=80%)  |
| `gts`         | Frontend lint + format |
| `addlicense`  | License headers        |
