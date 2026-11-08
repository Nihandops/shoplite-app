SHELL := /bin/bash
COMPOSE ?= docker compose
BASE_URL ?= http://localhost:8080/api

.PHONY: help env build up down clean test smoke logs ps lint

help: ## show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'

env:
	@test -f .env || cp .env.example .env

build: env ## build all images
	$(COMPOSE) build

up: env ## start the stack and wait until every service is healthy
	$(COMPOSE) up -d --build --wait --wait-timeout 180

down: ## stop the stack (keeps the postgres volume)
	$(COMPOSE) down

clean: ## stop the stack and delete volumes
	$(COMPOSE) down -v

test: ## run unit tests inside Docker (no local Python needed)
	docker build --target test -t shoplite/catalog-api:test services/catalog-api
	docker build --target test -t shoplite/order-worker:test services/order-worker

smoke: ## end-to-end smoke test against the running stack
	./scripts/smoke-test.sh $(BASE_URL)

logs: ## tail logs
	$(COMPOSE) logs -f --tail=100

ps:
	$(COMPOSE) ps

lint: ## hadolint + helm lint (needs docker)
	for f in services/*/Dockerfile; do docker run --rm -i hadolint/hadolint < $$f; done
	docker run --rm -v $(PWD)/helm:/helm alpine/helm:3.16.4 lint /helm/shoplite -f /helm/shoplite/values.yaml
