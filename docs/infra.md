# Integration with filoz-infra

This repo uses **Helm charts for local development**. The `filoz-infra` repo uses **Kustomize for production deployments** (staging/prod).

## Architecture

**Local Development (this repo)**:
- Helm chart in `charts/dealbot/`
- Uses Kind cluster with bundled PostgreSQL
- NodePort service mapped to localhost:8080
- Managed via Makefile targets (`make up`, `make deploy`, etc.)

**Production Deployments (filoz-infra repo)**:
- Kustomize-based manifests in `deployments/kubernetes/`
- Flux CD for GitOps deployment
- SOPS for secret encryption
- Managed PostgreSQL database

## Generating manifests for filoz-infra

To generate Kustomize-compatible manifests from this Helm chart:

```bash
# Generate base manifest
helm template dealbot ./charts/dealbot \
  -f ./charts/dealbot/values.yaml \
  --set postgresql.enabled=false \
  --set ingress.enabled=false \
  > manifest-output.yaml
```

The filoz-infra repo will then use Kustomize overlays to customize for each environment (staging/prod).

## Key differences

| Aspect | Local (Helm) | Production (Kustomize) |
|--------|--------------|------------------------|
| Tool | Helm chart | Kustomize overlays |
| Secrets | .env → k8s Secret | SOPS-encrypted files |
| Database | Bundled PostgreSQL | Managed database |
| Service | NodePort | ClusterIP + Ingress |
| CD | Manual (make deploy) | Flux CD |
