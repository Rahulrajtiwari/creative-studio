# Cloud Build pipelines

Three pipelines covering the full image -> deploy lifecycle on a fully private
GKE control plane:

| File                        | Purpose                                      |
|-----------------------------|----------------------------------------------|
| `cloudbuild-backend.yaml`   | Build, test, push, scan the FastAPI image    |
| `cloudbuild-frontend.yaml`  | Build, push, scan the Angular/Nginx image    |
| `cloudbuild-deploy.yaml`    | `helm upgrade --install` against private GKE |

## Required preconditions

- A **Cloud Build private worker pool** peered to the GKE cluster's VPC.
  This is the only Cloud Build runtime that can reach a fully private cluster
  control plane and Artifact Registry over private IP.
- A **dedicated builder service account** with these roles in the deploy
  project: `roles/artifactregistry.writer`, `roles/container.developer`,
  `roles/iam.workloadIdentityUser`, `roles/secretmanager.secretAccessor`.
- The Cloud SQL Proxy and other workload pods must already be running, so the
  Helm migrations Job can connect at deploy time.

## Suggested trigger model

```
github push -> branch: main
  ├── cloudbuild-backend.yaml   (path filter: backend/**)
  ├── cloudbuild-frontend.yaml  (path filter: frontend/**)
  └── manual / scheduled        (cloudbuild-deploy.yaml)
```

For production, pin `_BACKEND_IMAGE_TAG` and `_FRONTEND_IMAGE_TAG` to **image
digests** (`sha256:...`) rather than the short SHA tag. The build pipelines
emit a `*-image-pinned.txt` artifact containing the immutable digest reference;
consume that in the deploy step.
