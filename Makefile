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

.PHONY: clean
clean: ## Remove Terraform and Terragrunt cache and ephemeral files
	@echo "Cleaning Terraform and Terragrunt cache files..."
	@find . -depth -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -depth -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -exec rm -f {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate" -exec rm -f {} + 2>/dev/null || true
	@find . -type f -name "*.tfstate.backup" -exec rm -f {} + 2>/dev/null || true
	@find . -type f -name "*.tfplan" -exec rm -f {} + 2>/dev/null || true
	@find . -type f -name "crash.log" -exec rm -f {} + 2>/dev/null || true
	@echo "Clean complete!"

.PHONY: version
version: ## Show Terraform version
	terraform version
