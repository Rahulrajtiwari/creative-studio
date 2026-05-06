<div align="center">
  <img src="./screenshots/horizontal-creative-studio-next.png" alt="Creative Studio Hero Image" width="600">
  <br>
  <br>
  <h1 align="center">Google Cloud Creative Studio Platform</h1>
  <p align="center"><b>The First Google Cloud Open Source, All-in-One Agentic Studio <br> for Building High-Fidelity Multimedia Content 🚀</b></p>

  <p align="center">
    <img src="https://img.shields.io/badge/angular-%23DD0031.svg?style=for-the-badge&logo=angular&logoColor=white">
    <img src="https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi">
    <img src="https://img.shields.io/badge/google%20gemini-8E75B2?style=for-the-badge&logo=google%20gemini&logoColor=white">
    <img src="https://img.shields.io/badge/GoogleCloud-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white">
    <a href="https://github.com/pylint-dev/pylint"><img src="https://img.shields.io/badge/linting-pylint-yellowgreen?style=for-the-badge"></a>
    <a href="https://github.com/google/gts"><img src="https://img.shields.io/badge/code%20style-google-blueviolet.svg?style=for-the-badge"></a>
    <img src="https://img.shields.io/badge/tailwindcss-%2338B2AC.svg?style=for-the-badge&logo=tailwind-css&logoColor=white">
  </p>

</div>

---

Creative Studio is a comprehensive, all-in-one Generative AI platform designed as a deployable solution for your own Google Cloud project. It serves as a powerful reference implementation and creative suite, showcasing the full spectrum of Google's state-of-the-art generative AI models on Vertex AI.

Built for creators, marketers, and developers, this application provides a hands-on, interactive experience with cutting-edge multimodal capabilities.

> ###### _This is not an officially supported Google product. This project is not eligible for the [Google Open Source Software Vulnerability Rewards Program](https://bughunters.google.com/open-source-security)._

---

## ☁️ Google Cloud Next '26 & Izumi Integration

We are super excited to announce that we will be at **Google Cloud Next '26**! Our team will be attending and showcasing our deep integration with the **Izumi Agent**. 

Learn more about the multi-agent multimedia ecosystem at the [Izumi Agent Repository](https://github.com/GoogleCloudPlatform/genmedia-izumi-agent/tree/main).

---

## Core Features 🎨

Creative Studio goes beyond simple demos, implementing advanced, real-world features that developers can learn from and build upon:

**🎬 Advanced Video Generation (Veo):**

- Generate high-quality videos from text prompts.
- Utilize Image-to-Video (R2V) capabilities, allowing users to upload reference images.
- Differentiate between reference types, using images for ASSET consistency or STYLE transfer.

**🖼️ High-Fidelity Image Generation (Imagen):**

- Create stunning images from detailed text descriptions.
- Explore a wide range of creative styles, lighting, and composition controls.

**✍️ Gemini-Powered Prompt Engineering:**

- **Prompt Rewriting:** Automatically enhance and expand user prompts for superior generation results.
- **Multimodal Critic:** Use Gemini's multimodal understanding to evaluate and provide feedback on generated images.

**📄 Brand Guidelines Integration:**

- Upload PDF style guides that the backend processes to automatically infuse brand identity into generated content.
- Features a robust, scalable upload mechanism using GCS Signed URLs to bypass server timeouts and handle large files efficiently.

**👕 Virtual Try-On (VTO):**

- Includes functionality for seeding system-level assets like garments and models, laying the groundwork for virtual try-on applications.

## GenMedia Screenshots | Creative Studio

<p align="center">
  <img src="./screenshots/creative-studio-screenshots.gif" alt="Creative Studio Screenshots Walkthrough" width="800">
</p>


## Production Deployment (Private GKE)

Creative Studio is now packaged as a **fully-private**, enterprise-grade
application that runs on Google Kubernetes Engine. The application is **not
reachable from the public internet** — only users on the corporate network
(VDI, VPN, Cloud Interconnect, or a sanctioned corporate proxy) can access
the Internal HTTPS Load Balancer that fronts it.

The bootstrap script and Firebase Hosting / Cloud Run flow are no longer
supported. Use the Terraform stacks under `infra/environments/{dev,qat,prd}`
plus the Helm chart at `deploy/helm/creative-studio` instead.

### High-level architecture

```
Corporate User
   │  (VPN / VDI / Interconnect)
   ▼
Internal HTTPS Load Balancer  ◄── corp-issued TLS cert in Secret Manager
   │
   ▼
GKE Private Cluster (regional, private endpoint, Master Authorized Networks)
   ├─ frontend Deployment   ──► Nginx (non-root, 8080) serving Angular
   └─ backend  Deployment   ──► FastAPI (non-root, 8080)
                            └─ cloud-sql-proxy sidecar (--auto-iam-authn)
                                  │
                                  ▼
                          Private Cloud SQL (Postgres, PSA, IAM auth)
                                  │
                                  ▼
                          Private Service Connect ──► googleapis.com
                                                       (Vertex AI, GCS,
                                                        Secret Manager, ...)

Identity Provider (Ping / Okta / Entra ID) ── OIDC Auth Code + PKCE
```

Detailed walkthroughs live in [`DEVELOPMENT.md`](./DEVELOPMENT.md).

### Repository layout

| Path                                      | What's there                                                            |
|-------------------------------------------|-------------------------------------------------------------------------|
| `backend/`                                | FastAPI service, OIDC verifier, Cloud SQL Proxy-friendly DB layer       |
| `frontend/`                               | Angular SPA (`angular-auth-oidc-client`) + non-root Nginx runtime image |
| `infra/modules/network/`                  | VPC, subnets, PSA, PSC, NAT, private DNS, firewalls (BYO toggles)       |
| `infra/modules/gke-private/`              | Regional private GKE cluster + node pools                               |
| `infra/modules/cloudsql-private/`         | Private Cloud SQL PostgreSQL (PSA) with IAM auth                        |
| `infra/modules/gcs-private/`              | Hardened GCS buckets (UBLA, public-access prevention, scoped CORS)      |
| `infra/modules/artifact-registry/`        | Private Docker repo                                                     |
| `infra/modules/internal-lb-cert/`         | Regional SSL cert sourced from Secret Manager + reserved internal IP    |
| `infra/modules/workload-identity/`        | GSA ↔ KSA bindings                                                      |
| `infra/modules/platform-gke/`             | Wrapper that wires all the above into a single platform stack           |
| `infra/environments/{dev,qat,prd}/`       | Per-env Terraform roots with `*.tfvars.example` and remote state config |
| `deploy/helm/creative-studio/`            | Production Helm chart (HPA, PDB, NetworkPolicy, BackendConfig, ...)    |
| `deploy/kustomize/`                       | Kustomize overlays (renders the Helm chart with PSA labels)             |
| `deploy/cloudbuild/`                      | Cloud Build pipelines for backend, frontend, deploy (private pool)      |
| `deploy/argocd/`                          | Argo CD `AppProject` and `ApplicationSet` for GitOps                    |

### "Bring Your Own" (BYO) compatibility matrix

You may reuse existing infrastructure or have Terraform create new resources.
Whether you reuse or create, **all CIDR/network inputs are mandatory** so
operators avoid IP conflicts.

| Resource                       | Variable to reuse existing                          | Notes when creating new                                            |
|--------------------------------|-----------------------------------------------------|--------------------------------------------------------------------|
| VPC network                    | `network.existing_vpc_name`                         | Otherwise set `network.new_vpc_name`                               |
| GKE primary subnet             | `network.existing_gke_subnet_name`                  | Always provide `network.gke_subnet_cidr`                           |
| Pods/Services secondary ranges | `network.existing_pods_range_name` / `..._services` | Always provide `pods_secondary_cidr` / `services_secondary_cidr`   |
| Proxy-only subnet (ILB)        | `network.existing_proxy_only_subnet_name`           | Always provide `network.proxy_only_subnet_cidr`                    |
| GKE cluster                    | `gke.existing_cluster_name`                         | Always provide `gke.master_ipv4_cidr_block` and node-pool sizing   |
| Cloud SQL instance             | `cloudsql.existing_instance_name`                   | Always provide `cloudsql.psa_range_*`                              |
| GCS buckets                    | `gcs.existing_bucket_name_*`                        | Otherwise the chart creates buckets with UBLA + scoped CORS        |

### Authentication: OpenID Connect

Creative Studio integrates with **any standard OIDC IdP** — Ping, Okta,
Entra ID, Keycloak, etc. The frontend uses the
[`angular-auth-oidc-client`](https://www.npmjs.com/package/angular-auth-oidc-client)
library (Authorization Code + PKCE, silent renew via refresh tokens). The
backend verifies bearer JWTs against the IdP's JWKS, checking `iss`, `aud`,
`exp`, `nbf`, `email_verified`, allowed email domains, and group claims.

To onboard a new IdP, register a confidential client with:

- **Allowed callback** : `https://<corp-host>/`
- **Allowed logout**   : `https://<corp-host>/login`
- **Token endpoint authentication**: `none` (PKCE only) or `private_key_jwt`
- **Required scopes** : `openid`, `profile`, `email`, plus `offline_access`
  if your IdP requires it for refresh tokens
- **Required claims** : `email`, `email_verified`, `groups` (or the claim
  configured in `OIDC_ALLOWED_GROUPS_CLAIM`)

Then populate the `oidc.*` keys in `values-<env>.yaml` and the matching
`OIDC_*` Terraform variables in `infra/environments/<env>/<env>.tfvars`.

### Pipeline overview

1. **Terraform** (`infra/environments/<env>`) provisions the platform.
2. **Cloud Build** (`deploy/cloudbuild/cloudbuild-{backend,frontend}.yaml`)
   builds & scans images on a private worker pool, pushes them to Artifact
   Registry by digest, and writes a pinned `*-image-pinned.txt` artifact.
3. A CI bot updates `values-<env>.yaml` with the new digest and commits.
4. **Argo CD** (`deploy/argocd`) auto-syncs the Helm chart to the target
   cluster (or, alternatively, run `cloudbuild-deploy.yaml` to drive a
   `helm upgrade --install` directly).
5. **Helm pre-install/upgrade hook** runs Alembic migrations against
   Cloud SQL via the Cloud SQL Proxy sidecar before workloads start.

### Required GCP APIs

The platform Terraform automatically enables every API listed below in the
target project — operators do not need to enable them by hand.

- `aiplatform.googleapis.com` (Vertex AI)
- `artifactregistry.googleapis.com`
- `cloudbuild.googleapis.com`
- `compute.googleapis.com`
- `container.googleapis.com` (GKE)
- `containerfilesystem.googleapis.com` (image streaming)
- `dns.googleapis.com` (private DNS zones)
- `iam.googleapis.com`
- `iamcredentials.googleapis.com`
- `logging.googleapis.com` / `monitoring.googleapis.com`
- `secretmanager.googleapis.com`
- `servicenetworking.googleapis.com` (PSA)
- `sqladmin.googleapis.com` (Cloud SQL)
- `storage.googleapis.com`
- `texttospeech.googleapis.com`

### Operator tooling

- `gcloud` (Google Cloud SDK)
- `terraform` >= 1.6
- `helm` >= 3.13 (or `kustomize` >= 5 with `--enable-helm`)
- `kubectl` matching the cluster's minor version
- `git`, `jq`, `uv` (Python tooling for backend dev/test)

## 🛡️ Quality Standards & CI/CD

To ensure the highest level of quality and security, we enforce strict style guidelines and automated checks both locally and in our CI/CD pipeline.

### 🎨 Code Style Guidelines
- **Python**: We adhere to the [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html), using `pylint` and `black`.
- **TypeScript**: We follow the [Angular Coding Style Guide](https://angular.dev/style-guide) and [Google's TypeScript Style Guide](https://github.com/google/gts) using `gts`.
- **Commit Messages**: We suggest following [Angular's Commit Message Guidelines](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md).

### 🌿 Branching Model
We follow the [Git Flow](https://nvie.com/posts/a-successful-git-branching-model/) branching model. Please create feature branches from `dev` and submit pull requests back to `dev`.

### ⚙️ Automated Checks (Pre-commit & GitHub Actions)

Every Pull Request to `develop`, `test`, or `main` branches undergoes automated checks via GitHub Actions, and you can also run them locally:

- **Local Pre-commit Hook**: Runs in a Docker container on every commit to check styling and licenses. See the [Development Guide](./DEVELOPMENT.md#5-code-quality--pre-commit-hooks) for setup instructions.
- **Backend Tests**: Minimum **80%** code coverage enforced by `pytest-cov`.
- **Backend Linting**: Minimum score of **9.0/10** enforced by `pylint`.
- **Frontend Linting**: Enforced by `gts` in CI.
- **AI-Powered Review**: Automated reviews powered by Gemini to catch issues early.

## 🛠️ Contributing

We welcome contributions to Creative Studio! Whether it's new templates, features, bug fixes, or documentation improvements, your help is valued.

### Prerequisites for Contributing

- A **GitHub Account**.
- **2-Factor Authentication (2FA)** enabled on your GitHub account.
- Familiarity with the "Getting Started" section to set up your development environment.

For more detailed contribution guidelines, please refer to the `CONTRIBUTING.md` file.

### Local Development

For a comprehensive, step-by-step guide on how to set up and run Creative Studio on your local machine using Docker Compose, please refer to the [Local Development Guide](./DEVELOPMENT.md).

## Feedback

- **Found an issue or have a suggestion?** Please [raise an issue](https://github.com/GoogleCloudPlatform/gcc-creative-studio/issues) on our GitHub repository.
- **Share your experience!** We'd love to hear about how you're using Creative Studio or any success stories. Feel free to reach out to us at genmedia-creativestudio@google.com or discuss in the GitHub discussions.

# Relevant Terms of Service

[Google Cloud Platform TOS](https://cloud.google.com/terms)

[Google Cloud Privacy Notice](https://cloud.google.com/terms/cloud-privacy-notice)

# Responsible Use

Building and deploying generative AI agents requires a commitment to responsible development practices. Creative Studio provides to you the tools to build agents, but you must also provide the commitment to ethical and fair use of these agents. We encourage you to:

- **Start with a Risk Assessment:** Before deploying your agent, identify potential risks related to bias, privacy, safety, and accuracy.
- **Implement Monitoring and Evaluation:** Continuously monitor your agent's performance and gather user feedback.
- **Iterate and Improve:** Use monitoring data and user feedback to identify areas for improvement and update your agent's prompts and configuration.
- **Stay Informed:** The field of AI ethics is constantly evolving. Stay up-to-date on best practices and emerging guidelines.
- **Document Your Process:** Maintain detailed records of your development process, including data sources, models, configurations, and mitigation strategies.

# Disclaimer

**This is not an officially supported Google product.**

Copyright 2025 Google LLC. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
