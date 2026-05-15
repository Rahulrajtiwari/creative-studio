# 🚀 Creative Studio Deployment Guide

This guide provides definitive, production-grade instructions for deploying the Creative Studio multi-model content generation platform on Google Kubernetes Engine (GKE).

---

## Phase 0 — Prerequisites (One-time setup)

### 0.1 Tooling Matrix

Ensure the deployment workstation possesses the following core tooling ecosystem:

| Tool | Minimum Version | Installation Path | Purpose |
| :--- | :--- | :--- | :--- |
| `gcloud` | Latest | [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) | Core Google Cloud API interaction |
| `gke-gcloud-auth-plugin`| Latest | `gcloud components install gke-gcloud-auth-plugin` | Native GKE Kubernetes authentication |
| `terraform` | 1.6+ | `brew install terraform` | Infrastructure-as-Code orchestration |
| `helm` | 3.13+ | `brew install helm` | Kubernetes manifest templating and packaging |
| `kubectl` | 1.28+ | `gcloud components install kubectl` | Cluster control plane communication |
| `docker` | 24+ | Standard package | Direct runtime container compilation |
| `jq`, `git` | Standard | Base repository distribution | Manifest extraction utilities |

### 0.2 Architectural Access Scope

> [!IMPORTANT]
> **Public External Facing Architecture:** The ingress layer utilizes a **Global External Load Balancer (GLB)**. Consequently, the frontend static bundle landing page is publicly accessible over the open internet via standard HTTPS.
> 
> **Strict Domain Authorization:** To protect operational resources, authorization enforces mandatory **Domain Verification** at the single-page application boundary. Only corporate identities belonging to approved Google OpenID Connect domains (e.g., `ravitiwary.altostrat.com`) are allowed complete authentication workflows; all outside identities are dropped at the gateway.
> 
> **Private Infrastructure Egress:** The core database cluster, private GKE control plane endpoints, and internal Cloud Build private worker pools reside strictly on private RFC 1918 subnets. Operational configurations must originate from authenticated networks carrying GCP metadata server reachability.

---

## Phase 1 — Platform Bootstrap

### 1.1 Platform Authentication

Authenticate local Application Default Credentials (ADC) securely to your workspace:

```bash
export PROJECT_ID="ravi-argolis-01"
export REGION="asia-south1"

gcloud auth login --update-adc
gcloud config set project "$PROJECT_ID"
```

### 1.2 Persistent Remote State Bucket

Provision an unversioned state repository utilizing uniform IAM security validation:

```bash
export STATE_BUCKET="${PROJECT_ID}-tfstate"

gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```

### 1.3 Foundational GCP API Enforcement

Enable the standard platform management suite:

```bash
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"
```

### 1.4 Pre-Seeding Secret Manager Dependencies

Populate baseline keys consumed natively by the infrastructure modules:

**1. Database Backing Password (Fallback credentials payload)**
```bash
echo -n "$(openssl rand -base64 24)" | \
  gcloud secrets create creative-studio-db-password-dev \
    --replication-policy=automatic --data-file=-
```

**2. Ingress GLB Public TLS Certificate Chain (PEM formatted)**
```bash
gcloud secrets create creative-studio-dev-tls-crt \
  --replication-policy=automatic --data-file=./tls.crt
```

**3. Ingress GLB Private TLS Key (Unencrypted PEM)**
```bash
gcloud secrets create creative-studio-dev-tls-key \
  --replication-policy=automatic --data-file=./tls.key
```

> [!NOTE]
> Secret references match standardized variables defined within `dev.tfvars.example`.

---

## Phase 2 — Infrastructure-as-Code Provisioning

### 2.1 Environment Configuration Overlay

Establish target network topology constraints:

```bash
cd infra/environments/dev
cp dev.tfvars.example dev.tfvars
```

Validate critical overrides inside `dev.tfvars`:
- `project_id`: Set precisely to target project string.
- `network.*`: Non-overlapping local CIDR definitions.
- `app.oidc.*`: Client identification details targeting Google Single Sign-On target domains.

### 2.2 Initialize Backend Provider Hooks

```bash
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=creative-studio/dev"
```

### 2.3 Orchestrate Platform Convergence

```bash
terraform plan -var-file=dev.tfvars -out=tfplan
terraform apply tfplan
```
*(Estimated duration: 25 to 40 minutes)*

Extract dynamically allocated outputs upon execution:
```bash
terraform output -raw cluster_name
terraform output -raw cloudsql_connection_name
terraform output -raw backend_gsa_email
```
> [!TIP]
> Terraform generates the file **`generated/values-from-tf.yaml`** automatically. Preserve this artifact, as it serves as the baseline parameter map for target application containers.

### 2.4 Initialize Cloud SQL IAM Security Profiles

Bind database security mappings to support passwordless Application Default Credential handshakes:

```bash
GSA_EMAIL=$(terraform output -raw backend_gsa_email)
INSTANCE_NAME=$(terraform output -raw cloudsql_connection_name | cut -d: -f3)

gcloud sql users create "${GSA_EMAIL%.gserviceaccount.com}" \
  --instance="$INSTANCE_NAME" \
  --type=CLOUD_IAM_SERVICE_ACCOUNT
```

Execute schema allocation via a secure in-cluster operational debug client:
```bash
# 1. Authenticate local kubeconfig to target GKE control plane
gcloud container clusters get-credentials cs-dev --region=asia-south1 --project=ravi-argolis-01

# 2. Mount ephemeral debug terminal
kubectl run pg-client --rm -i --tty --image=postgres:15 --restart=Never -- psql "host=10.24.0.7 user=studio_user dbname=creative_studio"
```
Execute database role bindings:
```sql
GRANT ALL PRIVILEGES ON DATABASE creative_studio TO "cs-be-dev@ravi-argolis-01.iam";
GRANT ALL PRIVILEGES ON SCHEMA public TO "cs-be-dev@ravi-argolis-01.iam";
\q
```

---

## Phase 3 — Image Asset Packaging

Compile target binaries utilizing isolated runtime profiles.

### Option A — Distributed Cloud Build Pipeline (Production standard)

Execute container builds passing platform variables natively:
```bash
# Return to repository root directory
cd ../../../

# Submit production backend runner
gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-backend.yaml \
  --region="asia-south1" \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool,_AR_REPO=creative-studio-dev,_PROJECT_ID=ravi-argolis-01,_AR_REGION=asia-south1,_BUILD_ARTIFACTS_BUCKET=ravi-argolis-01-cs-dev

# Submit production frontend compilation
gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-frontend.yaml \
  --region="asia-south1" \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool,_AR_REPO=creative-studio-dev,_PROJECT_ID=ravi-argolis-01,_AR_REGION=asia-south1,_BUILD_ARTIFACTS_BUCKET=ravi-argolis-01-cs-dev
```

### Option B — Native Host Compilation

```bash
AR_URL="asia-south1-docker.pkg.dev/ravi-argolis-01/creative-studio-dev"
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet

docker build --platform=linux/amd64 --target=runtime -t "${AR_URL}/creative-studio-backend:bootstrap" backend/
docker push "${AR_URL}/creative-studio-backend:bootstrap"

docker build --platform=linux/amd64 --target=runtime -t "${AR_URL}/creative-studio-frontend:bootstrap" frontend/
docker push "${AR_URL}/creative-studio-frontend:bootstrap"
```

---

## Phase 4 — Kubernetes Topology Bootstrapping

Ensure access context targets internal control paths:
```bash
gcloud container clusters get-credentials cs-dev --region=asia-south1 --project=ravi-argolis-01
```

---

## Phase 5 — Foundational Cluster Operators

### 5.1 Distributed Secret Discovery Framework

Deploy standard open-source operational secret reconcilers:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true --version 0.10.4
```

Apply authentication store linking native workload identities:
```bash
kubectl apply -f deploy/helm/creative-studio/cluster-secret-store.yaml
```

### 5.2 Namespace Partitioning

Enforce baseline container isolation standards:
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: creative-studio
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
EOF
```

---

## Phase 6 — Operational Overlay Validation

Verify target override structures inside `deploy/helm/creative-studio/values-dev.yaml`. Ensure parameters enforce native runtime debugging safety checks:
- **Frontend Initialization (`initContainers`)**: Seeds `/usr/share/nginx/html/assets` dynamically to prevent `emptyDir` volume shadowing startup errors.
- **Backend Middleware Security (`TRUSTED_HOSTS`)**: Hardcoded wildcard mapping (`*`) permits generic IP headers on kubelet liveness and readiness probes.
- **Sidecar Clean Termination**: Enforces standard library post-hooks to stop the Cloud SQL Proxy dynamically via its admin endpoint once the `alembic` schema hook finishes.

---

## Phase 7 — Definitive Application Synchronization

> [!IMPORTANT]
> **Merge Order Integrity:** Helm merges overlay maps sequentially. To ensure that custom parameters (like explicit database mapping overrides) apply correctly, **always pass the generated base parameters file first, and your developer overrides overlay second.**

Execute pristine baseline rollout sequence:
```bash
cd deploy/helm/creative-studio

# Step 1: Seed primary resources instantly (Resolves circular dependency deadlocks)
helm install creative-studio . \
  -n creative-studio --create-namespace \
  --no-hooks \
  -f ../../infra/environments/dev/generated/values-from-tf.yaml \
  -f values-dev.yaml

# Step 2: Perform atomic release deployment sync
helm upgrade --install creative-studio . \
  -n creative-studio \
  --atomic --timeout 15m \
  -f ../../infra/environments/dev/generated/values-from-tf.yaml \
  -f values-dev.yaml
```

Monitor clean rollout convergence in real-time:
```bash
kubectl -n creative-studio get pods -w
```

---

## Phase 8 — External Access & Public Ingress Routing

### 8.1 Extract GLB Ingress Allocation

Identify the allocated public static Edge IP:
```bash
kubectl -n creative-studio get ingress creative-studio -o wide
```
*(Expected target string: **`34.13.79.67`**)*

### 8.2 Register Public Cloud DNS `A` Record

Because external users access the platform globally, map your endpoint domain to the Load Balancer IP.

**Console UI Method:**
1. Navigate to **Network services** → **Cloud DNS** inside the Google Cloud Console.
2. Select the managed zone responsible for your base domain (`ravitiwary.altostrat.com.`).
3. Click **+ ADD STANDARD (RECORD SET)**.
4. Specify DNS Name: `creative-studio` (evaluating to `creative-studio.ravitiwary.altostrat.com.`).
5. Resource Type: `A`, TTL: `300`, IPv4 Address: `34.13.79.67`.
6. Click **CREATE**.

**CLI Alternative:**
```bash
gcloud dns record-sets create creative-studio.ravitiwary.altostrat.com. \
  --rrdatas="34.13.79.67" --type="A" --ttl="300" \
  --zone="<YOUR_MANAGED_ZONE_NAME>" --project="ravi-argolis-01"
```

### 8.3 Immediate Validation via Local Hosts Mapping

To execute end-to-end smoke testing instantly without waiting for public DNS propagation, append the explicit route to your local workstation's hosts file (`/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`):
```text
34.13.79.67    creative-studio.ravitiwary.altostrat.com
```

Open your web browser and verify target load routing:
👉 **`https://creative-studio.ravitiwary.altostrat.com`**
- Landing UI loads public static assets securely over TLS.
- Sign-in validation interfaces correctly to external IdP flows.

---

## Phase 9 — Enterprise OpenID Connect (OIDC) & Multi-IdP Architecture

The Creative Studio platform enforces strict separation of concerns between immutable container build binaries and environmental runtime configurations. The exact same container image can be deployed across Dev, QAT, and PRD environments or switched across disparate Identity Providers (IdPs) without requiring a container rebuild.

### 9.1 Runtime Initialization Architecture
When the frontend container boots inside Kubernetes:
1. An `initContainer` (`init-assets`) mounts an ephemeral scratch volume (`emptyDir`) at `/usr/share/nginx/html/assets` and copies all immutable base templates into it.
2. Before starting Nginx, `docker-entrypoint.sh` executes `envsubst` against `runtime-config.template.json`, injecting the environmental parameters provided by the Kubernetes ConfigMap (`OIDC_AUTHORITY`, `OIDC_CLIENT_ID`, etc.) directly into `/usr/share/nginx/html/assets/runtime-config.json`.
3. The Angular Single Page Application (SPA) asynchronously fetches this unauthenticated configuration file during startup initialization, instantly adapting its authentication headers, SSO URLs, and token endpoints to the active environment.

### 9.2 Switching Identity Providers (Zero Code Changes)
To migrate authentication from Google Accounts to an enterprise IdP (e.g., Microsoft Entra ID, Okta, Ping Identity, Keycloak), update the environmental parameters inside your Helm overlay (`values-dev.yaml`) or Terraform variable definitions (`tfvars`):

```yaml
frontend:
  config:
    OIDC_AUTHORITY: "https://login.microsoftonline.com/<tenant_id>/v2.0" # Or https://dev-xxxx.okta.com/oauth2/default
    OIDC_CLIENT_ID: "<ENTRA_OR_OKTA_SPA_CLIENT_ID>"
    OIDC_AUDIENCE: "api://creative-studio-backend"
    OIDC_IDP_DISPLAY_NAME: "Sign in with Corporate SSO (Entra ID)"

backend:
  config:
    OIDC_ISSUER: "https://login.microsoftonline.com/<tenant_id>/v2.0"
    OIDC_AUDIENCE: "api://creative-studio-backend"
    OIDC_ALLOWED_EMAIL_DOMAINS: "ravitiwary.altostrat.com,yourcompany.com"
```

**Nginx Security Adjustment (`connect-src`):**
Ensure the top-level domain of your new IdP is added to the `connect-src` directive inside `frontend/nginx.conf` to allow client-side AJAX discovery requests:
```nginx
# For Microsoft Entra ID
connect-src 'self' https://login.microsoftonline.com https://*.googleapis.com;
```

### 9.3 Required OAuth 2.0 Resources & Credentials Matrix
When configuring identity resources across different providers, adhere to the following registration standards:

| Target IdP Ecosystem | Client Registration Type | Required Input Credentials | Architectural Rationale |
| :--- | :--- | :--- | :--- |
| **Google Accounts** *(Dual-Client Pattern)* | 1. **Web Application**<br>2. **Desktop App** *(Native)* | - Web App Client ID & Client Secret<br>- Desktop App Client ID *(Secretless)* | Google Web App IDs require a client secret on `/token` but allow custom web redirect URIs (`https://<fqdn>/`). Google Desktop App IDs require no secret but restrict redirects to loopback. The ultimate enterprise pattern pairs both: register custom HTTPS redirects on the Web App ID, and pass the secretless Desktop App ID to the SPA. |
| **Microsoft Entra ID** *(App Registrations)* | **Single Page Application (SPA)** | - SPA Client ID<br>*(No Client Secret)* | Entra ID natively issues secretless SPA client IDs supporting arbitrary custom HTTPS web redirect URIs with absolute PKCE validation out of the box. |
| **Okta / Ping Identity** | **Single Page Application (SPA)** | - SPA Client ID<br>*(No Client Secret)* | Okta and Ping Federate natively support secretless PKCE SPA client configurations. |

---

## Quick Verification Checklist

- [x] Infrastructure modules compiled successfully without state drift
- [x] Application Default Credentials bound natively to Cloud SQL IAM roles
- [x] Database users populated with complete DDL/DML public schema permission grants
- [x] Target SSL certificates and database keys pre-seeded inside Secret Manager
- [x] Build compilation tasks pushed clean layer checksums to Artifact Registry
- [x] Container deployment references target precise SHA digests
- [x] Target execution contexts operate under restricted security profiles
- [x] Initialization sequences seed cache layers perfectly to bypass file read blocks
- [x] Release steps report absolute success (`STATUS: deployed`)
- [x] Readiness paths validate complete API database access functionality
- [x] Global External Load Balancer backends evaluate to `HEALTHY` in Cloud Console
- [x] External domain name validation routes strictly authenticated corporate accounts
