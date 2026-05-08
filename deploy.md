# 🚀 Creative Studio Deployment Guide

This guide provides step-by-step instructions for deploying the Creative Studio platform on a private GKE cluster.

---

## Phase 0 — Prerequisites (One-time, on your laptop)

### 0.1 Tools you must have installed

| Tool | Min Version | Install Hint |
| :--- | :--- | :--- |
| `gcloud` | Latest | [Install Link](https://cloud.google.com/sdk/docs/install) |
| `gke-gcloud-auth-plugin` | Latest | `gcloud components install gke-gcloud-auth-plugin` |
| `terraform` | 1.6+ | `brew install terraform` |
| `helm` | 3.13+ | `brew install helm` |
| `kubectl` | Matches GKE (1.28+) | `gcloud components install kubectl` |
| `docker` | 24+ | For local image builds |
| `jq`, `git` | Any | Utility tools |

### 0.2 Network Access

> [!IMPORTANT]
> Because the cluster, Cloud SQL, and Artifact Registry are on private IPs (and the GKE control plane is private), the machine running the commands below **must be on the corporate network** (VDI, corporate VPN, Cloud Interconnect, or a sanctioned bastion / Cloud Workstations VM in the same VPC). A laptop on home Wi-Fi cannot talk to the private control plane directly. The Load Balancer is now Global and External, so the application itself will be accessible publicly.

### 0.3 What you must have ready before you start

1.  **Target GCP Project**: One per environment (e.g., `creative-studio-dev`, `creative-studio-qat`, `creative-studio-prd`).
2.  **CIDR Allocation**: Approved by your network team for:
    *   GKE nodes subnet, pods secondary, services secondary, proxy-only subnet, PSC subnet + IP, PSA range, GKE master CIDR.
    *   *Examples are in `infra/environments/dev/dev.tfvars.example`.*
3.  **OIDC Client Registered in your IdP** (Ping/Okta/Entra ID). You need:
    *   Issuer URL (e.g., `https://login.microsoftonline.com/<tenant>/v2.0`)
    *   Audience(s) (the API identifier)
    *   Frontend Client ID (the SPA client ID)
    *   Allowed callback `https://<corp-host>/`, allowed logout `https://<corp-host>/login`
    *   Scopes: `openid`, `profile`, `email`
    *   A groups (or equivalent) claim mapped from your directory.
4.  **Corporate DNS Name**: (e.g., `creative-studio.dev.corp.example.com`) you can point to a private IP.
5.  **TLS Certificate + Key**: For that hostname, signed by your corporate PKI (PEM format).
6.  **Internet Access for Jumpbox/VM**: Ensure the machine you use for deployment has internet access (via Cloud NAT or Public IP) to download the Cloud SQL Auth Proxy and talk to Google APIs.
7.  **Cloud Build Public Egress**: The private worker pool needs public egress enabled to fetch Debian packages during the build, unless you mirror all package repositories.

---

## Phase 1 — Bootstrap the GCP project

### 1.1 Authenticate

```bash
export PROJECT_ID="ravi-argolis-01"
export REGION="asia-south1"
export VPC =""


gcloud auth login
gcloud auth application-default login
gcloud config set project "$PROJECT_ID"
```

### 1.2 Create a GCS bucket for Terraform state (One-time)

```bash
export STATE_BUCKET="${PROJECT_ID}-tfstate"

gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```

### 1.3 Enable the bootstrap APIs
The platform Terraform enables most APIs itself, but Terraform needs Service Usage on the first run:

```bash
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"
```

### 1.4 Upload secrets into Secret Manager
The platform reads three secrets at apply time. Create each one and add a version. For the TLS cert/key files, use whatever your PKI gave you.

**1. Cloud SQL DB password (for non-IAM fallback / break-glass)**
```bash
echo -n "$(openssl rand -base64 24)" | \
  gcloud secrets create creative-studio-db-password-dev \
    --replication-policy=automatic --data-file=-
```

**2. GLB TLS certificate (PEM, full chain)**
```bash
gcloud secrets create creative-studio-dev-tls-crt \
  --replication-policy=automatic --data-file=./tls.crt
```

**3. GLB TLS private key (PEM)**
```bash
gcloud secrets create creative-studio-dev-tls-key \
  --replication-policy=automatic --data-file=./tls.key
```

> [!NOTE]
> Secret IDs above match the defaults in `dev.tfvars.example`; if you change them, update the `cloudsql.db_password_secret_id` and `lb_config.{cert_pem_secret_id,key_pem_secret_id}` values too.

---

## Phase 2 — Provision the private platform with Terraform

### 2.1 Configure the env root

```bash
cd infra/environments/dev
cp dev.tfvars.example dev.tfvars
```

Edit `dev.tfvars` and fill in every `REPLACE_*` placeholder. The values that matter most:
*   `project_id`
*   `network.{nodes_cidr, pods_cidr, services_cidr, proxy_only_subnet_cidr, psc_subnet_cidr, psc_googleapis_ip, psa_range_cidr}` — must not overlap with existing on-prem ranges.
*   `network.master_authorized_cidrs` — the only CIDRs that can reach the GKE control plane (your VPN + VDI ranges).
*   `gke.master_cidr` — `/28` for the private control plane endpoint.
*   `lb_config.lb_static_ip_address` — leave empty to let GCP allocate a public IP for the GLB.
*   `app.fqdn` — the corp DNS name.
*   `app.oidc.{issuer, audiences, frontend_client_id, allowed_email_domains, allowed_groups}`.
*   `gcs.cors_origins` — must equal `["https://<app.fqdn>"]`, nothing wider.

### 2.2 Wire up the remote state backend
`backend.tf` already declares a GCS backend; pass the bucket created in Step 1.2:

```bash
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=creative-studio/dev"
```

### 2.3 Plan + Apply

```bash
terraform plan -var-file=dev.tfvars -out=tfplan
terraform apply tfplan
```
*Apply takes 25–40 minutes (Cloud SQL alone is ~15 min).*

When it finishes, capture the outputs:
```bash
terraform output -raw cluster_name
terraform output -raw cluster_location
terraform output -raw artifact_registry_url
terraform output -raw cloudsql_connection_name
terraform output -raw lb_static_ip_address
terraform output -raw backend_gsa_email
```
The env root also rendered `generated/values-from-tf.yaml`. Keep this path — you will pass it to Helm.

### 2.4 Bootstrap the Cloud SQL IAM database user
The backend authenticates to Cloud SQL using the GSA you bound to the `creative-studio-backend` KSA via Workload Identity. Create the matching DB role:

```bash
# 1. Make sure the GSA_EMAIL variable is set (just in case it was lost)
GSA_EMAIL=$(terraform output -raw backend_gsa_email)

# 2. Create the user with the correct instance name
gcloud sql users create "${GSA_EMAIL%.gserviceaccount.com}" \
  --instance="cs-pg-dev-b38e7508" \
  --type=CLOUD_IAM_SERVICE_ACCOUNT

```

or 

```bash
INSTANCE_NAME=$(terraform output -raw cloudsql_connection_name | cut -d: -f3)

gcloud sql users create "${GSA_EMAIL%.gserviceaccount.com}" \
  --instance="$INSTANCE_NAME" \
  --type=CLOUD_IAM_SERVICE_ACCOUNT
```
Then connect once as a Postgres superuser and grant `creative-studio-backend` permission on the `creative_studio` database.

You have two options to do this, depending on your network access:

#### Option A: Using the GKE Cluster (Recommended & Foolproof)
This method launches a temporary pod inside your cluster to connect to the database, bypassing any local network issues on your machine.

1.  **Authenticate to the GKE cluster**:
    ```bash
    gcloud container clusters get-credentials cs-dev --region=asia-south1 --project=ravi-argolis-01
    ```
2.  **Run a temporary Postgres client pod and connect**:
    ```bash
    kubectl run pg-client --rm -i --tty --image=postgres:15 --restart=Never -- psql "host=10.24.0.7 user=studio_user dbname=creative_studio"
    ```
    *   When prompted for the password, retrieve it from Secret Manager (Step 2 below) and paste it.
3.  **Run the SQL commands** (see Step 4 below).

#### Option B: Using the Cloud SQL Auth Proxy
Use this method if your machine is on the corporate network (VPN/VDI) and can route to the database IP.

**Step 1: Download the Cloud SQL Auth Proxy**
```bash
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.11.0/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy
```
*(For Mac, use `cloud-sql-proxy.darwin.amd64` or `cloud-sql-proxy.darwin.arm64`)*

**Step 2: Retrieve the Database Password**
```bash
gcloud secrets versions access latest --secret="creative-studio-db-password-dev"
```
*(Copy the output password)*

**Step 3: Start the Proxy**
```bash
CONNECTION_NAME=$(terraform output -raw cloudsql_connection_name)

# If running on a GCE VM with default scopes, you must force it to use your user credentials:
export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json

# Start the proxy using the Private IP
./cloud-sql-proxy --private-ip $CONNECTION_NAME
```
*(Wait until you see "The proxy has started successfully")*

**Step 4: Connect and Grant Permissions**
Open a new terminal window and connect to the database:

*   **If using local psql**:
    ```bash
    psql "host=127.0.0.1 user=studio_user dbname=creative_studio"
    ```
*   **If using Docker** (cleaner if you don't have `psql` installed):
    ```bash
    docker run -it --rm --net=host postgres:15 psql "host=127.0.0.1 user=studio_user dbname=creative_studio"
    ```

Once connected, run these SQL commands:
```sql
-- Grant connect permission to the database
GRANT ALL PRIVILEGES ON DATABASE creative_studio TO "cs-be-dev@ravi-argolis-01.iam";

-- Grant permissions on the public schema (needed to create tables)
GRANT ALL PRIVILEGES ON SCHEMA public TO "cs-be-dev@ravi-argolis-01.iam";
```
*Note: The username must be in quotes because it contains the `@` character.*

Type `\q` and press Enter to exit. You can now stop the Cloud SQL proxy (`Ctrl+C`).

You are now fully ready to proceed to Phase 3 and build the application images!

---

## Phase 3 — Build & Push the container images
You can build either with Cloud Build (recommended) or locally. Pick one.

### 3.0 Optional: Mirror external base images (Required for private worker pools)
If you are using a private worker pool with `--no-public-egress` enabled, the build workers cannot access the public internet to pull external base images (like GitHub Container Registry). You must mirror them to your private Artifact Registry first.

Follow these steps from a machine that has internet access (like your jumpbox after adding the egress allow rule):

**1. Install Docker (if not present) and configure permissions**:
```bash
sudo apt-get update && sudo apt-get install -y docker.io

# Add your user to the docker group to avoid using sudo for docker commands
sudo usermod -aG docker $USER
newgrp docker
```

**2. Pull the image from GitHub**:
```bash
docker pull ghcr.io/astral-sh/uv:python3.12-bookworm-slim
```

**3. Tag and Push to your Artifact Registry**:
```bash
# Authenticate docker to your registry
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet

# Tag the image for your registry
docker tag ghcr.io/astral-sh/uv:python3.12-bookworm-slim asia-south1-docker.pkg.dev/ravi-argolis-01/creative-studio-dev/uv-base:latest

# Push it
docker push asia-south1-docker.pkg.dev/ravi-argolis-01/creative-studio-dev/uv-base:latest
```

**4. Update the Dockerfile**:
Update your application's `Dockerfile` (e.g., `backend/Dockerfile`) to use the mirrored image:
```dockerfile
FROM asia-south1-docker.pkg.dev/ravi-argolis-01/creative-studio-dev/uv-base:latest
```

### 3.1 Option A — Cloud Build private worker pool (Recommended)

```bash

#change the directory to the base directory of creative-studio


# Create the pool once (in the same VPC as GKE so it can reach AR privately)
gcloud builds worker-pools create creative-studio-pool \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --peered-network="projects/${PROJECT_ID}/global/networks/cs-vpc-dev" \
  --no-public-egress

*Note: The backend build now runs unit tests inside the Dockerfile. If tests fail, the build will fail.*

# Trigger the pipelines
gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-backend.yaml \
  --region="asia-south1" \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool,_AR_REPO=creative-studio-dev,_PROJECT_ID=ravi-argolis-01,_AR_REGION=asia-south1,_BUILD_ARTIFACTS_BUCKET=ravi-argolis-01-cs-dev



gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-frontend.yaml \
  --region="asia-south1" \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool,_AR_REPO=creative-studio-dev,_PROJECT_ID=ravi-argolis-01,_AR_REGION=asia-south1,_BUILD_ARTIFACTS_BUCKET=ravi-argolis-01-cs-dev


```
Each build emits a `*-image-pinned.txt` artifact in `gs://${_BUILD_ARTIFACTS_BUCKET}/....` Grab the digest:

```bash

git rev-parse --short HEAD

gcloud storage cat \
  "gs://<artifacts-bucket>/creative-studio-dev/creative-studio-backend/<sha>/backend-image-pinned.txt"
```

### 3.2 Option B — Build locally (Only for first-time bring-up)

```bash
AR_URL=$(cd infra/environments/dev && terraform output -raw artifact_registry_url)
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Backend
docker build --platform=linux/amd64 --target=runtime \
  -t "${AR_URL}/creative-studio-backend:bootstrap" backend/
docker push "${AR_URL}/creative-studio-backend:bootstrap"

# Frontend
docker build --platform=linux/amd64 --target=runtime \
  -t "${AR_URL}/creative-studio-frontend:bootstrap" frontend/
docker push "${AR_URL}/creative-studio-frontend:bootstrap"
```
Resolve the immutable digest once pushed (use this in `values-dev.yaml`, not the tag):

```bash
gcloud artifacts docker images describe \
  "${AR_URL}/creative-studio-backend:bootstrap" \
  --format='value(image_summary.digest)'
```

---

## Phase 4 — Connect to the private GKE cluster

```bash
gcloud container clusters get-credentials \
  "$(terraform -chdir=infra/environments/dev output -raw cluster_name)" \
  --region "$REGION" \
  --internal-ip \
  --project "$PROJECT_ID"

kubectl get nodes        # Smoke test
```
> [!WARNING]
> If `get-credentials --internal-ip` times out, your VPN/VDI route to `gke.master_cidr` is missing — fix that before continuing.

---

## Phase 5 — Install cluster prerequisites
These are one-time installs per cluster.

### 5.1 External Secrets Operator (Recommended for production secrets)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true \
  --version 0.10.4
```
Create a `ClusterSecretStore` that authenticates to GCP Secret Manager via Workload Identity:

```yaml
# cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: creative-studio-dev
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: cs-dev
          serviceAccountRef:
            name: creative-studio-backend
            namespace: creative-studio
```
```bash
kubectl apply -f cluster-secret-store.yaml
```

### 5.2 Application namespace with Pod Security Admission labels

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: creative-studio
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
```

---

## Phase 6 — Tune the Helm values for this environment
Open `deploy/helm/creative-studio/values-dev.yaml` and verify these match the Terraform outputs.

---

## Phase 7 — Deploy the application
The Helm pre-install hook runs Alembic before the app pods come up, so a single command handles migrations + rollout.

```bash
cd deploy/helm/creative-studio
helm upgrade --install creative-studio . \
  -n creative-studio \
  --atomic --timeout 15m \
  -f values-dev.yaml \
  -f ../../infra/environments/dev/generated/values-from-tf.yaml
```

Watch the rollout:
```bash
kubectl -n creative-studio get pods -w
kubectl -n creative-studio rollout status deploy/creative-studio-backend
kubectl -n creative-studio rollout status deploy/creative-studio-frontend
```

Confirm readiness:
```bash
kubectl -n creative-studio exec deploy/creative-studio-backend -c app -- \
  wget -qO- http://localhost:8080/readyz
# Expected: {"db":true,"oidc":true}
```

---

## Phase 8 — Wire up DNS and reach the app

### 8.1 Get the GLB IP

```bash
kubectl -n creative-studio get ingress creative-studio -o wide
```
*Look at the ADDRESS column.*

### 8.2 Create the DNS A record
Point your DNS name to the new External IP:
`creative-studio.ravitiwary.altostrat.com.   IN  A   <GLB external IP>`

### 8.3 Verify backend health from Cloud Console
In the Cloud Console, go to **Network services** → **Load balancing** → your GLB → **Backends**. All NEG endpoints (frontend + backend) must show **HEALTHY**.

If any show UNHEALTHY:
```bash
kubectl -n creative-studio describe backendconfig
kubectl -n creative-studio describe ingress creative-studio
kubectl -n creative-studio logs deploy/creative-studio-backend -c app --tail=200
```

### 8.4 Smoke test from a corp-network host
Open a browser on a VDI/VPN-connected machine: `https://creative-studio.dev.corp.example.com`

You should:
1.  Get redirected to your IdP.
2.  Sign in with an allowed user.
3.  Land on the Creative Studio home page.

---

## Phase 9 — (Optional) Switch to GitOps with Argo CD

```bash
# Install Argo CD privately
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.4/manifests/install.yaml

# Register the app
kubectl apply -n argocd -f deploy/argocd/project.yaml
kubectl apply -n argocd -f deploy/argocd/applicationset.yaml
```

---

## Phase 10 — Promote to QAT and PRD
Repeat Phases 1 to 8 in `infra/environments/qat` and `infra/environments/prd`, switching the values overlay file.

---

## Quick Checklist

- [ ] Terraform apply finished without errors
- [ ] `cloudsql_connection_name` output is in your Helm values
- [ ] DB IAM user created
- [ ] DB role granted on the `creative_studio` database
- [ ] TLS cert + key + DB password secrets exist in Secret Manager
- [ ] Cloud Build private pool (or local docker push) produced AR images
- [ ] Helm values point to image digests, not `:latest`
- [ ] External Secrets Operator + ClusterSecretStore installed
- [ ] Namespace has the `pod-security.kubernetes.io/enforce=restricted` label
- [ ] `helm upgrade --install` returned `STATUS: deployed`
- [ ] `/readyz` returns `{"db":true,"oidc":true}`
- [ ] All ILB backends are **HEALTHY** in Cloud Console
- [ ] DNS A record points to the ILB internal IP
- [ ] OIDC redirect URI in the IdP exactly matches `https://<fqdn>/`
