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

## Updating filoz-infra from this Helm chart

When updating the filoz-infra Kustomize manifests based on changes to this Helm chart:

### Step 1: Generate base manifests

```bash
# From this dealbot repo root
helm template dealbot ./charts/dealbot \
  -f ./charts/dealbot/values.yaml \
  --set postgresql.enabled=false \
  --set ingress.enabled=false \
  --set image.repository=dealbot \
  --set image.tag=latest \
  > /tmp/dealbot-manifests.yaml
```

### Step 2: Split into separate files

The filoz-infra repo expects separate files per resource type. Split the generated manifest:

```bash
# Example structure in filoz-infra:
# /Users/sgtpooki/code/work/filoz/filecoin-project/filoz-infra/deployments/kubernetes/base/dealbot/
# ├── deployment.yaml
# ├── service.yaml
# ├── serviceaccount.yaml
# ├── configmap.yaml
# └── kustomization.yaml
```

Use `kubectl-slice` or manually split `/tmp/dealbot-manifests.yaml` into separate files.

### Step 3: Update kustomization.yaml

The base kustomization.yaml should reference all resources:

```yaml
# base/dealbot/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - serviceaccount.yaml
  - configmap.yaml
```

### Step 4: Key differences to handle

When adapting Helm output for Kustomize, watch for:

1. **ConfigMap**: Helm creates `dealbot-env` ConfigMap. In filoz-infra, this is generated via:
   ```yaml
   # staging/kustomization.yaml
   configMapGenerator:
     - name: dealbot-config
       files:
         - dealbot-config.env
   ```

2. **Secrets**: Helm uses `existingSecret`. In filoz-infra, use:
   ```yaml
   secretGenerator:
     - name: dealbot-secrets
       files:
         - dealbot-secrets.env.encrypted  # SOPS-encrypted
   ```

3. **Image references**: Kustomize overlays replace images:
   ```yaml
   # prod/kustomization.yaml
   images:
     - name: dealbot
       newName: 941641221830.dkr.ecr.us-east-1.amazonaws.com/filoz-dealbot
       newTag: latest # {"$imagepolicy": "dealbot:prod-dealbot"}
   ```

4. **Service**: Change from NodePort (local) to ClusterIP (prod)
5. **Resource naming**: Kustomize uses `namePrefix` (e.g., `prod-`, `staging-`)

### Step 5: Test locally before committing

```bash
cd /Users/sgtpooki/code/work/filoz/filecoin-project/filoz-infra/deployments/kubernetes/us-east-1/f3-passive-testing/dealbot/staging
kustomize build .
kubectl apply --dry-run=server -k .
```

## Initial Deployment to filoz-infra

When deploying dealbot to filoz-infra for the first time:

1. **Create environment-specific config files**:
   ```bash
   # In filoz-infra repo
   touch deployments/kubernetes/us-east-1/f3-passive-testing/dealbot/staging/dealbot-config.env
   touch deployments/kubernetes/us-east-1/f3-passive-testing/dealbot/prod/dealbot-config.env
   ```

2. **Create SOPS-encrypted secrets**:
   ```bash
   # Create unencrypted template
   cat > /tmp/dealbot-secrets.env <<EOF
   WALLET_PRIVATE_KEY=0x...
   WALLET_ADDRESS=f1...
   DATABASE_PASSWORD=...
   EOF

   # Encrypt with SOPS (requires AWS credentials and KMS access)
   cd deployments/kubernetes/us-east-1/f3-passive-testing/dealbot/staging
   sops -e /tmp/dealbot-secrets.env > dealbot-secrets.env.encrypted
   rm /tmp/dealbot-secrets.env
   ```

3. **Set database connection**: Update DATABASE_HOST in config.env to point to managed PostgreSQL (not bundled)

4. **Configure ingress**: Update ingress-patch.yaml with actual hostname and TLS settings

5. **Verify image registry**: Ensure ECR image names match in kustomization.yaml images section

## Key differences

| Aspect | Local (Helm) | Production (Kustomize) |
|--------|--------------|------------------------|
| Tool | Helm chart | Kustomize overlays |
| Secrets | .env → k8s Secret | SOPS-encrypted files |
| Database | Bundled PostgreSQL | Managed database |
| Service | NodePort | ClusterIP + Ingress |
| CD | Manual (make deploy) | Flux CD |
