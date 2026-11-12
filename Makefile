.DEFAULT_GOAL := ci

BIN := $(CURDIR)/.bin
export PATH := $(BIN):$(PATH)

# Recipes call the tools through these, because GNU Make 3.81 (the macOS default) looks up a
# simple command in its own PATH, not the exported one above. The pinned copies in .bin/ win.
OPA := $(firstword $(wildcard $(BIN)/opa) opa)
REGAL := $(firstword $(wildcard $(BIN)/regal) regal)

VERSION ?= dev
COVERAGE_THRESHOLD ?= 90

# Rego that the static checks and tests cover: the library, integration adapters that need only OPA,
# and the trace replay tooling.
REGO_DIRS := policies/ integrations/agentgateway/policy/ scripts/replay/

# The trace that `make replay` checks, and the config that was live when it was recorded.
TRACE ?= examples/trace/decision-log.jsonl
CONFIG ?= $(wildcard packs/*/data.example.json)

.PHONY: tools fmt fmt-check check lint test coverage fixtures replay qa bundle config-bundle e2e e2e-docker ci clean

tools: ## Install pinned OPA and Regal into .bin/
	sh scripts/install-tools.sh

fmt: ## Rewrite Rego files in canonical format
	$(OPA) fmt --write $(REGO_DIRS)

fmt-check: ## Fail if any Rego file is not canonically formatted
	@test -z "$$($(OPA) fmt --list $(REGO_DIRS))" || { echo "needs opa fmt:"; $(OPA) fmt --list $(REGO_DIRS); exit 1; }
	$(OPA) fmt --diff --fail $(REGO_DIRS)

check: ## Compile with strict checks
	$(OPA) check --strict $(REGO_DIRS)

lint: ## Run Regal
	$(REGAL) lint $(REGO_DIRS)

test: ## Run Rego unit tests
	$(OPA) test $(REGO_DIRS)

coverage: ## Run unit tests and enforce the coverage threshold
	$(OPA) test --coverage --threshold $(COVERAGE_THRESHOLD) $(REGO_DIRS) > coverage.json || { \
		sh scripts/coverage-report.sh coverage.json; exit 1; }
	@sh scripts/coverage-report.sh coverage.json

fixtures: ## Validate fixtures and examples against the schemas and check their outcomes
	sh scripts/check-fixtures.sh

replay: ## Replay a recorded decision log; fails when any call's outcome moved. TRACE=<log> CONFIG=<data.json ...>
	sh scripts/replay.sh $(TRACE) $(CONFIG)

qa: ## Repository quality gates: contracts, neutrality, pack completeness, docs
	sh scripts/qa.sh

bundle: ## Build the policy bundle at dist/mcp-policy-library.tar.gz
	mkdir -p dist
	$(OPA) build --bundle policies/ --ignore '*_test.rego' --revision $(VERSION) --output dist/mcp-policy-library.tar.gz

config-bundle: ## Build dist/config.tar.gz from every pack's data.example.json
	sh scripts/build-config-bundle.sh dist/config.tar.gz

e2e: bundle ## End-to-end test against a real OPA server over HTTP
	sh scripts/e2e.sh

e2e-docker: bundle config-bundle ## End-to-end test of the docker compose sidecar example (needs Docker)
	sh scripts/e2e-docker.sh

ci: fmt-check check lint coverage fixtures replay qa e2e ## Everything CI runs, except the Docker test

clean:
	rm -rf dist coverage.json
