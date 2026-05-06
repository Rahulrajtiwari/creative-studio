# Argo CD GitOps for Creative Studio

This directory contains the Argo CD `AppProject` and `ApplicationSet` that
manage Creative Studio across the dev / qat / prd clusters.

## How to install

1. Install Argo CD into the management cluster (or per-cluster) via your
   standard platform tooling. **The Argo CD UI/API must NOT be exposed on
   the public internet.** Use an Internal HTTPS LB, just like the application
   itself.
2. Apply this directory:

   ```bash
   kubectl apply -n argocd -f deploy/argocd/project.yaml
   kubectl apply -n argocd -f deploy/argocd/applicationset.yaml
   ```

3. Wire up CI image bumps. After each successful image build, the CI bot
   (Cloud Build trigger) must commit a one-line update to `values-<env>.yaml`:

   ```yaml
   backend:
     image:
       tag: sha256:abcdef...           # from /workspace/backend-image-pinned.txt
   frontend:
     image:
       tag: sha256:123456...
   migrations:
     image:
       tag: sha256:abcdef...
   ```

   Argo CD's `automated.syncPolicy` then rolls the change out within seconds.

## Why ApplicationSet?

A single object generates one Application per cluster (`gke-dev`, `gke-qat`,
`gke-prd`), so the same chart is deployed identically everywhere with only
the values overlay changing. Adding a new environment is a 5-line list entry.
