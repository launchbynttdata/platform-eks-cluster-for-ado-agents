# Makefile for ADO Agent EKS Cluster Infrastructure

.DEFAULT_GOAL := help

LAYERED_DIR := infrastructure-layered

.PHONY: help
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: test
test: ## Run layered infrastructure tests (ShellCheck, BATS, Checkov)
	cd $(LAYERED_DIR) && $(MAKE) test

.PHONY: test-quick
test-quick: ## Run ShellCheck and BATS only
	cd $(LAYERED_DIR) && $(MAKE) shellcheck bats-test

.PHONY: shellcheck
shellcheck: ## Run ShellCheck on deploy.sh
	cd $(LAYERED_DIR) && $(MAKE) shellcheck

.PHONY: bats-test
bats-test: ## Run BATS unit tests
	cd $(LAYERED_DIR) && $(MAKE) bats-test

.PHONY: checkov
checkov: ## Run Checkov security scan on Terraform layers
	cd $(LAYERED_DIR) && $(MAKE) checkov

.PHONY: go-static
go-static: ## Run Go vulnerability and static analysis for the ADO KEDA proxy
	cd app/ado-keda-proxy && go vet ./...
	cd app/ado-keda-proxy && go run golang.org/x/vuln/cmd/govulncheck@latest ./...
	cd app/ado-keda-proxy && go run github.com/securego/gosec/v2/cmd/gosec@latest ./...
	cd app/ado-keda-proxy && go run honnef.co/go/tools/cmd/staticcheck@latest ./...
	cd app/ado-keda-proxy && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest run --timeout=5m --enable-only=errcheck,govet,staticcheck,unused,ineffassign,bodyclose,noctx,contextcheck,errorlint,nilerr,unconvert ./...

.PHONY: clean-tf
clean-tf: ## Remove Terraform and Terragrunt cache, plans, local state, and generated files
	@echo "Cleaning Terraform and Terragrunt artifacts..."
	@find . -depth -type d \( -name ".terraform" -o -name ".terragrunt-cache" \) -exec rm -rf {} + 2>/dev/null || true
	@find . -type f \( \
		-name ".terraform.lock.hcl" -o \
		-name ".terraform.tfstate.lock.info" -o \
		-name "*.tfstate" -o \
		-name "*.tfstate.backup" -o \
		-name "backend_generated.tf" -o \
		-name "provider_generated.tf" -o \
		-name "k8s_provider_generated.tf" -o \
		-name "crash.log" \
	\) -exec rm -f {} + 2>/dev/null || true
	@find . -type f -name "crash.*.log" -exec rm -f {} + 2>/dev/null || true
	@find . -type f \( -name "*.tfstate.*" -o -name "*.tfplan" -o -name "*tfplan*" \) -exec rm -f {} + 2>/dev/null || true
	@echo "Terraform/Terragrunt clean complete."

.PHONY: clean
clean: clean-tf ## Alias for clean-tf

.PHONY: version
version: ## Show Terraform version
	terraform version
