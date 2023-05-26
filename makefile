# ==============================================================================
# Running from within k8s/kind

GOLANG          := golang:1.20
ALPINE          := alpine:3.18
KIND            := kindest/node:v1.27.2
POSTGRES        := postgres:15.3
TELEPRESENCE    := datawire/tel2:2.13.2

KIND_CLUSTER    := ardan-starter-cluster
NAMESPACE       := sales-system
APP             := sales
BASE_IMAGE_NAME := ardanlabs/service
SERVICE_NAME    := sales-api
VERSION         := 0.0.1
SERVICE_IMAGE   := $(BASE_IMAGE_NAME)/$(SERVICE_NAME):$(VERSION)

# ==============================================================================
# Install dependencies

dev-docker:
	docker pull $(GOLANG)
	docker pull $(ALPINE)
	docker pull $(KIND)
	docker pull $(POSTGRES)
	docker pull $(TELEPRESENCE)


# ==============================================================================
# Building containers

all: service

service:
	docker build \
		-f zarf/docker/dockerfile.service \
		-t $(SERVICE_IMAGE) \
		--build-arg BUILD_REF=$(VERSION) \
		--build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \


# ==============================================================================
# Running from within k8s/kind

dev-up-local:
	kind create cluster \
		--image $(KIND) \
		--name $(KIND_CLUSTER) \
		--config zarf/k8s/dev/kind-config.yaml

	kubectl wait --timeout=120s --namespace=local-path-storage --for=condition=Available deployment/local-path-provisioner

dev-down-local:
	kind delete cluster --name $(KIND_CLUSTER)


# ==============================================================================

dev-load:
	cd zarf/k8s/dev/sales; kustomize edit set image service-image=$(SERVICE_IMAGE)
	kind load docker-image $(SERVICE_IMAGE) --name $(KIND_CLUSTER)

dev-apply:
	kustomize build zarf/k8s/dev/sales | kubectl apply -f -
	kubectl wait pods --namespace=$(NAMESPACE) --selector app=$(APP) --for=condition=Ready

dev-restart:
	kubectl rollout restart deployment $(APP) --namespace=$(NAMESPACE)

dev-update: all dev-load dev-restart

dev-update-apply: all dev-load dev-apply

# ------------------------------------------------------------------------------

dev-logs:
	kubectl logs --namespace=$(NAMESPACE) -l app=$(APP) --all-containers=true -f --tail=100 --max-log-requests=6 | go run app/tooling/logfmt/main.go -service=$(SERVICE_NAME)

dev-logs-init:
	kubectl logs --namespace=$(NAMESPACE) -l app=$(APP) -f --tail=100 -c init-vault-system
	kubectl logs --namespace=$(NAMESPACE) -l app=$(APP) -f --tail=100 -c init-vault-loadkeys
	kubectl logs --namespace=$(NAMESPACE) -l app=$(APP) -f --tail=100 -c init-migrate
	kubectl logs --namespace=$(NAMESPACE) -l app=$(APP) -f --tail=100 -c init-seed

dev-status:
	kubectl get nodes -o wide
	kubectl get svc -o wide
	kubectl get pods -o wide --watch --all-namespaces

dev-describe:
	kubectl describe nodes
	kubectl describe svc

dev-describe-deployment:
	kubectl describe deployment --namespace=$(NAMESPACE) $(APP)

dev-describe-sales:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=$(APP)

# ------------------------------------------------------------------------------

dev-services-delete:
	kustomize build zarf/k8s/dev/sales | kubectl delete -f -

dev-describe-replicaset:
	kubectl get rs
	kubectl describe rs --namespace=$(NAMESPACE) -l app=$(APP)

dev-events:
	kubectl get ev --sort-by metadata.creationTimestamp

dev-events-warn:
	kubectl get ev --field-selector type=Warning --sort-by metadata.creationTimestamp

dev-shell:
	kubectl exec --namespace=$(NAMESPACE) -it $(shell kubectl get pods --namespace=$(NAMESPACE) | grep sales | cut -c1-26) --container sales-api -- /bin/sh

# ==============================================================================
# Administration

token-gen:
	go run app/tooling/sales-admin/main.go gentoken 5cf37266-3473-4006-984f-9325122678b7 54bb2165-71e1-41a6-af3e-7da4a0e1e2c1

# ==============================================================================
# Hitting endpoints

token-local:
	curl -il --user "admin@example.com:gophers" http://localhost:3000/v1/users/token/54bb2165-71e1-41a6-af3e-7da4a0e1e2c1

token:
	curl -il --user "admin@example.com:gophers" http://$(SERVICE_NAME).$(NAMESPACE).svc.cluster.local:3000/v1/users/token/54bb2165-71e1-41a6-af3e-7da4a0e1e2c1

# export TOKEN="COPY TOKEN STRING FROM LAST CALL"

users-local:
	curl -il -H "Authorization: Bearer ${TOKEN}" http://localhost:3000/v1/users?page=1&rows=2

users:
	curl -il -H "Authorization: Bearer ${TOKEN}" http://$(SERVICE_NAME).$(NAMESPACE).svc.cluster.local:3000/v1/users?page=1&rows=2

load-local:
	hey -m GET -c 100 -n 10000 -H "Authorization: Bearer ${TOKEN}" "http://localhost:3000/v1/users?page=1&rows=2"

load:
	hey -m GET -c 100 -n 10000 -H "Authorization: Bearer ${TOKEN}" "http://$(SERVICE_NAME).$(NAMESPACE).svc.cluster.local:3000/v1/users?page=1&rows=2"

# ==============================================================================
# Modules support

deps-reset:
	git checkout -- go.mod
	go mod tidy
	go mod vendor

tidy:
	go mod tidy
	go mod vendor

deps-list:
	go list -m -u -mod=readonly all

deps-upgrade:
	go get -u -v ./...
	go mod tidy
	go mod vendor

deps-cleancache:
	go clean -modcache

list:
	go list -mod=mod all