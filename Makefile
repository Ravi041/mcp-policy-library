.DEFAULT_GOAL := ci

BIN := $(CURDIR)/.bin
export PATH := $(BIN):$(PATH)

VERSION ?= dev
COVERAGE_THRESHOLD ?= 90

.PHONY: tools fmt fmt-check check lint test coverage fixtures qa bundle config-bundle e2e e2e-docker ci clean

tools: ## Install pinned OPA and Regal into .bin/
	sh scripts/install-tools.sh

fmt: ## Rewrite Rego files in canonical format
	opa fmt --write policies/

fmt-check: ## Fail if any Rego file is not canonically formatted
	@test -z "$$(opa fmt --list policies/)" || { echo "needs opa fmt:"; opa fmt --list policies/; exit 1; }
	opa fmt --diff --fail policies/

check: ## Compile with strict checks
	opa check --strict policies/

lint: ## Run Regal
	regal lint policies/

test: ## Run Rego unit tests
	opa test policies/

coverage: ## Run unit tests and enforce the coverage threshold
	opa test --coverage --threshold $(COVERAGE_THRESHOLD) policies/ > coverage.json || { \
		sh scripts/coverage-report.sh coverage.json; exit 1; }
	@sh scripts/coverage-report.sh coverage.json

fixtures: ## Validate fixtures and examples against the schemas and check their outcomes
	sh scripts/check-fixtures.sh

qa: ## Repository quality gates: contracts, neutrality, pack completeness, docs
	sh scripts/qa.sh

bundle: ## Build the policy bundle at dist/mcp-policy-library.tar.gz
	mkdir -p dist
	opa build --bundle policies/ --ignore '*_test.rego' --revision $(VERSION) --output dist/mcp-policy-library.tar.gz

config-bundle: ## Build dist/config.tar.gz from every pack's data.example.json
	sh scripts/build-config-bundle.sh dist/config.tar.gz

e2e: bundle ## End-to-end test against a real OPA server over HTTP
	sh scripts/e2e.sh

e2e-docker: bundle config-bundle ## End-to-end test of the docker compose sidecar example (needs Docker)
	sh scripts/e2e-docker.sh

ci: fmt-check check lint coverage fixtures qa e2e ## Everything CI runs, except the Docker test

clean:
	rm -rf dist coverage.json
