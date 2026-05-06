# Kustomize overlays for Creative Studio

These overlays render the Helm chart at `deploy/helm/creative-studio` through
the Kustomize Helm Chart Inflator and let you layer cluster-/environment-
specific resources (Namespace with Pod Security Admission labels, etc.).

## Prerequisites

- `kustomize` >= v5
- `helm` >= 3.13 on `$PATH`
- `--enable-helm` flag (Kustomize >= v5 requires this when using `helmCharts`)

## Build & apply

```bash
# Render only
kustomize build --enable-helm deploy/kustomize/overlays/dev

# Render + apply
kustomize build --enable-helm deploy/kustomize/overlays/dev | \
  kubectl apply -f -
```

## Why Helm + Kustomize together?

The Helm chart is the single source of truth for templates and values.
Kustomize overlays add cluster-level concerns that don't belong inside the
chart, such as:

- Namespace creation with Pod Security Admission labels (`restricted`).
- Adding `commonLabels` (e.g. `environment=prd`) across every resource.
- Inserting `NetworkPolicy` overrides per cluster (corp PSA CIDRs).
- Optional `ResourceQuota` or `LimitRange` definitions per environment.

If you prefer a pure Helm flow, deploy the chart directly with
`helm upgrade --install -f deploy/helm/creative-studio/values-<env>.yaml ...`.
The Helm chart and these Kustomize overlays produce identical workload
manifests.
