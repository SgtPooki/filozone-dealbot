KIND_CLUSTER ?= dealbot-local
KIND_CONFIG ?= kind-config.yaml
NAMESPACE ?= dealbot
CHART_PATH ?= charts/dealbot
VALUES_LOCAL ?= $(CHART_PATH)/values.local.yaml
DEFAULT_VALUES_EXTRA := $(wildcard $(CHART_PATH)/values.local.override.yaml)
VALUES_EXTRA ?= $(DEFAULT_VALUES_EXTRA)
IMAGE_REPO ?= dealbot-local
IMAGE_TAG ?= dev
HELM_ARGS ?=
SECRET_NAME ?= dealbot-secrets
SECRET_ENV_FILE ?= .env

.PHONY: kind-up kind-down deploy undeploy image-build kind-load helm-lint render logs namespace secret local-up up down

kind-up:
	kind create cluster --name $(KIND_CLUSTER) --config $(KIND_CONFIG)

kind-down:
	-kind delete cluster --name $(KIND_CLUSTER)

namespace:
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

image-build:
	docker build -t $(IMAGE_REPO):$(IMAGE_TAG) .

kind-load:
	kind load docker-image $(IMAGE_REPO):$(IMAGE_TAG) --name $(KIND_CLUSTER)

undeploy:
	helm uninstall dealbot --namespace $(NAMESPACE)

helm-lint:
	helm lint $(CHART_PATH) -f $(VALUES_LOCAL) $(if $(VALUES_EXTRA),-f $(VALUES_EXTRA)) $(HELM_ARGS)

render:
	helm template dealbot $(CHART_PATH) -f $(VALUES_LOCAL) $(if $(VALUES_EXTRA),-f $(VALUES_EXTRA)) $(HELM_ARGS)

logs:
	kubectl logs -n $(NAMESPACE) deploy/dealbot -f

secret: namespace
	@if [ -n "$(SECRET_ENV_FILE)" ]; then \
		if [ ! -f "$(SECRET_ENV_FILE)" ]; then echo "SECRET_ENV_FILE $(SECRET_ENV_FILE) not found"; exit 1; fi; \
		set -a; . $(SECRET_ENV_FILE); set +a; \
	fi; \
	if [ -z "$$WALLET_PRIVATE_KEY" ]; then echo "WALLET_PRIVATE_KEY is required (set in env or $(SECRET_ENV_FILE))"; exit 1; fi; \
	if [ -z "$$WALLET_ADDRESS" ]; then echo "WALLET_ADDRESS is required (set in env or $(SECRET_ENV_FILE))"; exit 1; fi; \
	SECRET_ARGS="--from-literal=WALLET_PRIVATE_KEY=$$WALLET_PRIVATE_KEY --from-literal=WALLET_ADDRESS=$$WALLET_ADDRESS"; \
	if [ -n "$$DATABASE_PASSWORD" ]; then \
		SECRET_ARGS="$$SECRET_ARGS --from-literal=DATABASE_PASSWORD=$$DATABASE_PASSWORD"; \
	fi; \
	kubectl -n $(NAMESPACE) create secret generic $(SECRET_NAME) \
		$$SECRET_ARGS \
		--dry-run=client -o yaml | kubectl apply -f -

deploy:
	@if [ -n "$(SECRET_ENV_FILE)" ]; then \
		if [ ! -f "$(SECRET_ENV_FILE)" ]; then echo "SECRET_ENV_FILE $(SECRET_ENV_FILE) not found"; exit 1; fi; \
	else \
		if [ -z "$$WALLET_PRIVATE_KEY" ]; then echo "WALLET_PRIVATE_KEY env var is required (or set SECRET_ENV_FILE)"; exit 1; fi; \
		if [ -z "$$WALLET_ADDRESS" ]; then echo "WALLET_ADDRESS env var is required (or set SECRET_ENV_FILE)"; exit 1; fi; \
	fi
	$(MAKE) secret SECRET_ENV_FILE=$(SECRET_ENV_FILE)
	helm upgrade --install dealbot $(CHART_PATH) \
		--namespace $(NAMESPACE) \
		-f $(VALUES_LOCAL) $(if $(VALUES_EXTRA),-f $(VALUES_EXTRA)) \
		--set image.repository=$(IMAGE_REPO) \
		--set image.tag=$(IMAGE_TAG) \
		--set existingSecret=$(SECRET_NAME) \
		$(HELM_ARGS)

local-up:
	$(MAKE) image-build
	$(MAKE) kind-load
	$(MAKE) deploy

up:
	$(MAKE) kind-up
	$(MAKE) local-up

down:
	$(MAKE) undeploy || true
	$(MAKE) kind-down
