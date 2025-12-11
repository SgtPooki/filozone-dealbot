# Local Kubernetes Development (Kind + Helm)

This repo ships the `dealbot` Helm chart. Local clusters use the same chart that staging/production consume from `filoz-infra` (env-specific values stay there).

## Prerequisites
- Docker, Kind, kubectl, Helm, make installed.

## One-time setup
```bash
make kind-up
cp charts/dealbot/values.local.override.example.yaml charts/dealbot/values.local.override.yaml
```
This creates the Kind cluster (`dealbot-local`) and prepares a gitignored override file for your local tweaks.
Service is exposed via NodePort 30081 with Kind host port mapping to 8080, so http://localhost:8080 should work without port-forwarding.

## Secrets (wallets are required, DB password is optional)
Secrets can be provided via `.env` file (recommended) or `values.local.override.yaml` (gitignored):

**Option 1: Using .env file (recommended for secrets)**
```bash
cp .env.example .env            # if you don't already have one
echo "WALLET_PRIVATE_KEY=..." >> .env
echo "WALLET_ADDRESS=..." >> .env
# Optional: add DATABASE_PASSWORD if using external DB
echo "DATABASE_PASSWORD=..." >> .env
make secret                     # uses SECRET_ENV_FILE=.env by default
```
The `make secret` target will add DATABASE_PASSWORD to the Kubernetes secret if it's set.

**Option 2: Using values.local.override.yaml**
```yaml
# values.local.override.yaml (gitignored)
existingSecret: dealbot-secrets  # Point to your secret
env:
  DATABASE_HOST: my-external-db.example.com
  DATABASE_USER: myuser
  # ... other overrides
```

**Note**: The bundled PostgreSQL uses a default password (`dealbot_password`). Only set DATABASE_PASSWORD if connecting to an external database.

## Build and deploy locally
```bash
make image-build                                    # docker build -t dealbot-local:dev .
make kind-load                                      # load the image into Kind
make deploy                                         # creates secret, then helm upgrade --install; auto-includes values.local.override.yaml if present
```
Access the app at http://localhost:8080.

Shortcut (after the cluster exists): one command builds, loads, creates secrets, and deploys:
```bash
make local-up
```

Sugar commands:
- `make up`   -> kind-up + local-up (cluster + secrets + build/load + deploy)
- `make down` -> undeploy app and delete the Kind cluster

## Values and overrides
- Default: `charts/dealbot/values.yaml`
- Local defaults (ingress, bundled Postgres): `charts/dealbot/values.local.yaml`
- Your overrides (gitignored): `charts/dealbot/values.local.override.yaml` (template provided)

`make deploy` will automatically include `charts/dealbot/values.local.override.yaml` if the file exists. Override it via `VALUES_EXTRA=...` if you want to point at a different file or skip it.

If you see `ErrImagePull` for `dealbot-local:dev`, rebuild and reload into Kind before deploying:
```bash
make image-build
make kind-load
make deploy
```

After changing Kind config or the service NodePort, recreate the cluster to pick up port mappings:
```bash
make down
make up
```

## Managing the release
```bash
make logs       # follow application logs
make undeploy   # helm uninstall dealbot
make kind-down  # delete the Kind cluster
```

## SOPS/External Secrets parity
If you want to reuse SOPS-managed secrets from the infra repo:
```bash
sops -d path/to/dealbot.enc.yaml > /tmp/dealbot-secrets.env
kubectl -n dealbot create secret generic dealbot-secrets --from-env-file=/tmp/dealbot-secrets.env
make deploy VALUES_EXTRA=charts/dealbot/values.local.override.yaml \
  HELM_ARGS="--set existingSecret=dealbot-secrets"
```
Or set `existingSecret: dealbot-secrets` in your gitignored override file. If you prefer External Secrets, install the operator in Kind, have it create the Secret, and point `existingSecret` at it.
