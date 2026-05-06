Phase 0 — Prerequisites (one-time, on your laptop)
0.1 Tools you must have installed
Tool	Min version	Install hint
gcloud
latest
https://cloud.google.com/sdk/docs/install
gke-gcloud-auth-plugin
latest
gcloud components install gke-gcloud-auth-plugin
terraform
1.6+
brew install terraform
helm
3.13+
brew install helm
kubectl
matches GKE (1.28+)
gcloud components install kubectl
docker
24+
for local image builds
jq, git
any
utility
0.2 Network access
Because the cluster, Cloud SQL, ILB and Artifact Registry are all on private IPs, the machine running the commands below must be on the corporate network (VDI, corporate VPN, Cloud Interconnect, or a sanctioned bastion / Cloud Workstations VM in the same VPC). A laptop on home Wi-Fi cannot talk to the private control plane.

0.3 What you must have ready before you start
A target GCP project (one per env: creative-studio-dev, creative-studio-qat, creative-studio-prd).
CIDR allocation approved by your network team:
GKE nodes subnet, pods secondary, services secondary, proxy-only subnet, PSC subnet + IP, PSA range, GKE master CIDR. Examples are in infra/environments/dev/dev.tfvars.example.
An OIDC client registered in your IdP (Ping/Okta/Entra ID). You need:
issuer URL (e.g. https://login.microsoftonline.com/<tenant>/v2.0)
audience(s) (the API identifier)
frontend_client_id (the SPA client ID)
Allowed callback https://<corp-host>/, allowed logout https://<corp-host>/login
Scopes openid profile email
A groups (or equivalent) claim mapped from your directory
A corporate DNS name (e.g. creative-studio.dev.corp.example.com) you can point to a private IP.
A TLS cert + key for that hostname, signed by your corporate PKI (PEM format).
Phase 1 — Bootstrap the GCP project
1.1 Authenticate
export PROJECT_ID="creative-studio-dev"
export REGION="us-central1"
gcloud auth login
gcloud auth application-default login
gcloud config set project "$PROJECT_ID"
1.2 Create a GCS bucket for Terraform state (one-time)
export STATE_BUCKET="${PROJECT_ID}-tfstate"
gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --uniform-bucket-level-access \
  --public-access-prevention
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
1.3 Enable the bootstrap APIs
The platform Terraform enables most APIs itself, but Terraform needs Service Usage on first run:

gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"
1.4 Upload secrets into Secret Manager
The platform reads three secrets at apply time. Create each one and add a version. For the TLS cert/key files use whatever your PKI gave you.

# 1. Cloud SQL DB password (for non-IAM fallback / break-glass)
echo -n "$(openssl rand -base64 24)" | \
  gcloud secrets create creative-studio-db-password-dev \
    --replication-policy=automatic --data-file=-
# 2. ILB TLS certificate (PEM, full chain)
gcloud secrets create creative-studio-dev-tls-crt \
  --replication-policy=automatic --data-file=./tls.crt
# 3. ILB TLS private key (PEM)
gcloud secrets create creative-studio-dev-tls-key \
  --replication-policy=automatic --data-file=./tls.key
Secret IDs above match the defaults in dev.tfvars.example; if you change them, update the cloudsql.db_password_secret_id and ilb_cert.{cert_pem_secret_id,key_pem_secret_id} values too.

Phase 2 — Provision the private platform with Terraform
2.1 Configure the env root
cd infra/environments/dev
cp dev.tfvars.example dev.tfvars
Edit dev.tfvars and fill in every REPLACE_* placeholder. The values that matter most:

project_id
network.{nodes_cidr, pods_cidr, services_cidr, proxy_only_subnet_cidr, psc_subnet_cidr, psc_googleapis_ip, psa_range_cidr} — must not overlap with existing on-prem ranges; your network team needs to bless these.
network.master_authorized_cidrs — the only CIDRs that can reach the GKE control plane (your VPN + VDI ranges).
gke.master_cidr — /28 for the private control plane endpoint.
ilb_cert.ilb_static_ip_address — a free IP inside network.nodes_cidr that the ILB will use.
app.fqdn — the corp DNS name.
app.oidc.{issuer, audiences, frontend_client_id, allowed_email_domains, allowed_groups}.
gcs.cors_origins — must equal ["https://<app.fqdn>"], nothing wider.
2.2 Wire up the remote state backend
backend.tf already declares a GCS backend; pass the bucket created in 1.2:

terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=creative-studio/dev"
2.3 Plan + apply
terraform plan  -var-file=dev.tfvars -out=tfplan
terraform apply tfplan
Apply takes 25–40 minutes (Cloud SQL alone is ~15 min). When it finishes, capture the outputs:

terraform output -raw cluster_name
terraform output -raw cluster_location
terraform output -raw artifact_registry_url
terraform output -raw cloudsql_connection_name
terraform output -raw ilb_static_ip_address
terraform output -raw backend_gsa_email
The env root also rendered generated/values-from-tf.yaml. Keep this path — you will pass it to Helm.

2.4 Bootstrap the Cloud SQL IAM database user
The backend authenticates to Cloud SQL using the GSA you bound to the creative-studio-backend KSA via Workload Identity. Create the matching DB role:

GSA_EMAIL=$(terraform output -raw backend_gsa_email)
gcloud sql users create "${GSA_EMAIL%.gserviceaccount.com}" \
  --instance="$(terraform output -raw cluster_name | sed 's/-cluster$//')" \
  --type=CLOUD_IAM_SERVICE_ACCOUNT
Then connect once (via the proxy) as a Postgres superuser and grant creative-studio-backend permission on the creative_studio database — your DBA has the playbook for this; the only things the GSA strictly needs are CONNECT, USAGE on public, and CREATE (only during migration runs). Update backend.config.DB_USER in your Helm values to the GSA short name (everything before @).

Phase 3 — Build & push the container images
You can build either with Cloud Build (recommended) or locally. Pick one.

3.1 Option A — Cloud Build private worker pool (recommended)
# create the pool once (in the same VPC as GKE so it can reach AR privately)
gcloud builds worker-pools create creative-studio-pool \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --peered-network="projects/${PROJECT_ID}/global/networks/cs-vpc-dev" \
  --no-public-egress
# trigger the pipelines
gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-backend.yaml \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool,_AR_REPO=creative-studio-dev
gcloud builds submit \
  --config=deploy/cloudbuild/cloudbuild-frontend.yaml \
  --substitutions=_PRIVATE_POOL_NAME=creative-studio-pool,_AR_REPO=creative-studio-dev
Each build emits a *-image-pinned.txt artifact in gs://${_BUILD_ARTIFACTS_BUCKET}/.... Grab the digest:

gcloud storage cat \
  "gs://<artifacts-bucket>/creative-studio-dev/creative-studio-backend/<sha>/backend-image-pinned.txt"
3.2 Option B — Build locally (only for first-time bring-up)
AR_URL=$(cd infra/environments/dev && terraform output -raw artifact_registry_url)
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
# backend
docker build --platform=linux/amd64 --target=runtime \
  -t "${AR_URL}/creative-studio-backend:bootstrap" backend/
docker push "${AR_URL}/creative-studio-backend:bootstrap"
# frontend
docker build --platform=linux/amd64 --target=runtime \
  -t "${AR_URL}/creative-studio-frontend:bootstrap" frontend/
docker push "${AR_URL}/creative-studio-frontend:bootstrap"
Resolve the immutable digest once pushed (use this in values-dev.yaml, not the tag):

gcloud artifacts docker images describe \
  "${AR_URL}/creative-studio-backend:bootstrap" \
  --format='value(image_summary.digest)'
Phase 4 — Connect to the private GKE cluster
gcloud container clusters get-credentials \
  "$(terraform -chdir=infra/environments/dev output -raw cluster_name)" \
  --region "$REGION" \
  --internal-ip \
  --project "$PROJECT_ID"
kubectl get nodes        # smoke test
If get-credentials --internal-ip times out, your VPN/VDI route to gke.master_cidr is missing — fix that before continuing.

Phase 5 — Install cluster prerequisites
These are one-time installs per cluster.

5.1 External Secrets Operator (recommended for production secrets)
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true \
  --version 0.10.4
Create a ClusterSecretStore that authenticates to GCP Secret Manager via Workload Identity (using the backend GSA):

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
kubectl apply -f cluster-secret-store.yaml
5.2 Application namespace with Pod Security Admission labels
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
Phase 6 — Tune the Helm values for this environment
Open deploy/helm/creative-studio/values-dev.yaml and verify these match the Terraform outputs:

values-dev.yaml key	Source
global.projectId
terraform output project_id
global.appHost
app.fqdn from your tfvars
image.registry
terraform output artifact_registry_url
backend.image.tag / frontend.image.tag / migrations.image.tag
digest from Phase 3 (e.g. sha256:abcd...)
backend.serviceAccount.googleServiceAccount
terraform output backend_gsa_email
cloudSqlProxy.instanceConnectionName
terraform output cloudsql_connection_name
ingress.preSharedCertName
terraform output ilb_certificate_name
ingress.staticIpName
name of the reserved IP from internal-lb-cert module
backend.config.OIDC_* and frontend.config.OIDC_*
from your IdP
networkPolicies.egress.cloudSqlPsaCidrs
[ network.psa_range_cidr ]
(generated/values-from-tf.yaml already contains most of these, so you can layer it on top instead.)

Phase 7 — Deploy the application
The Helm pre-install hook runs Alembic before the app pods come up, so a single command handles migrations + rollout.

cd deploy/helm/creative-studio
helm upgrade --install creative-studio . \
  -n creative-studio \
  --atomic --timeout 15m \
  -f values-dev.yaml \
  -f ../../infra/environments/dev/generated/values-from-tf.yaml
Watch the rollout:

kubectl -n creative-studio get pods -w
kubectl -n creative-studio rollout status deploy/creative-studio-backend
kubectl -n creative-studio rollout status deploy/creative-studio-frontend
Confirm readiness:

kubectl -n creative-studio exec deploy/creative-studio-backend -c app -- \
  wget -qO- http://localhost:8080/readyz
# expected: {"db":true,"oidc":true}
Phase 8 — Wire up DNS and reach the app
8.1 Get the ILB IP
kubectl -n creative-studio get ingress creative-studio -o wide
# look at the ADDRESS column; should match terraform output ilb_static_ip_address
8.2 Create the corporate DNS A record
Ask your DNS team to add an internal A record:

creative-studio.dev.corp.example.com.   IN  A   <ILB internal IP>
(or use a private Cloud DNS zone you own and attach it to the VPC).

8.3 Verify backend health from Cloud Console
In the Cloud Console go to Network services → Load balancing → your ILB → Backends. All NEG endpoints (frontend + backend) must show HEALTHY. If any show UNHEALTHY:

kubectl -n creative-studio describe backendconfig
kubectl -n creative-studio describe ingress creative-studio
kubectl -n creative-studio logs deploy/creative-studio-backend -c app --tail=200
8.4 Smoke test from a corp-network host
Open a browser on a VDI/VPN-connected machine: https://creative-studio.dev.corp.example.com

You should:

Get redirected to your IdP.
Sign in with a user whose email matches OIDC_ALLOWED_EMAIL_DOMAINS and who is in one of the OIDC_ALLOWED_GROUPS.
Land on the Creative Studio home page.
If sign-in fails, the most common culprits are listed at the bottom of DEVELOPMENT.md (section 4.8).

Phase 9 — (Optional) Switch to GitOps with Argo CD
Once the manual install is healthy, switch to Argo CD for ongoing deployments:

# install Argo CD privately
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.4/manifests/install.yaml
# expose Argo's UI through the SAME internal LB pattern (NOT publicly)
# ... (your standard Argo CD ingress recipe) ...
# register the app
kubectl apply -n argocd -f deploy/argocd/project.yaml
kubectl apply -n argocd -f deploy/argocd/applicationset.yaml
From now on, every CI image build commits a digest bump into values-dev.yaml; Argo CD auto-syncs within ~30 seconds.

Phase 10 — Promote to QAT and PRD
Repeat Phase 1 → Phase 8 in infra/environments/qat and infra/environments/prd, switching the values overlay file to values-qat.yaml / values-prd.yaml. The only structural differences are larger replica counts and gke.deletion_protection = true in production.

Quick "did I forget anything?" checklist

 Terraform apply finished without errors

 cloudsql_connection_name output is in your Helm values

 DB IAM user created (gcloud sql users create ... --type=CLOUD_IAM_SERVICE_ACCOUNT)

 DB role granted on the creative_studio database

 TLS cert + key + DB password secrets exist in Secret Manager

 Cloud Build private pool (or local docker push) produced AR images

 Helm values point to image digests, not :latest

 External Secrets Operator + ClusterSecretStore installed

 Namespace has the pod-security.kubernetes.io/enforce=restricted label

 helm upgrade --install returned STATUS: deployed

 /readyz returns {"db":true,"oidc":true}

 All ILB backends are HEALTHY in Cloud Console

 DNS A record points to the ILB internal IP

 OIDC redirect URI in the IdP exactly matches https://<fqdn>/
If any of these is unchecked, jump back to the corresponding phase above. Want me to bake this into a DEPLOYMENT.md file in the repo so your team can follow it without leaving the codebase?
