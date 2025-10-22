# Makefile for ADO Agent EKS Cluster Infrastructure

# Default target
.DEFAULT_GOAL := help

# Variables
TERRAFORM_DIR := infrastructure
CHECKOV_CONFIG := --quiet --compact

# Help target
.PHONY: help
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Initialize Terraform
.PHONY: init
init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	cd $(TERRAFORM_DIR) && terraform init

# Validate Terraform configuration
.PHONY: validate
validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	cd $(TERRAFORM_DIR) && terraform validate

# Format Terraform code
.PHONY: fmt
fmt: ## Format Terraform code
	@echo "Formatting Terraform code..."
	cd $(TERRAFORM_DIR) && terraform fmt --recursive

# Check formatting
.PHONY: fmt-check
fmt-check: ## Check if Terraform code is formatted
	@echo "Checking Terraform formatting..."
	cd $(TERRAFORM_DIR) && terraform fmt --recursive --check

# Run security scan with Checkov
.PHONY: checkov
checkov: ## Run security scan with Checkov
	@echo "Running Checkov security scan..."
	cd $(TERRAFORM_DIR) && checkov -d . $(CHECKOV_CONFIG)

# Run security scan with detailed output
.PHONY: checkov-detailed
checkov-detailed: ## Run Checkov security scan with detailed output
	@echo "Running detailed Checkov security scan..."
	cd $(TERRAFORM_DIR) && checkov -d .

# Plan Terraform deployment
.PHONY: plan
plan: ## Create Terraform execution plan
	@echo "Creating Terraform execution plan..."
	cd $(TERRAFORM_DIR) && terraform plan

# Apply Terraform configuration (with confirmation)
.PHONY: apply
apply: ## Apply Terraform configuration
	@echo "Applying Terraform configuration..."
	cd $(TERRAFORM_DIR) && terraform apply

# Apply Terraform configuration (auto-approve)
.PHONY: apply-auto
apply-auto: ## Apply Terraform configuration without confirmation
	@echo "Applying Terraform configuration (auto-approve)..."
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve

# Destroy Terraform infrastructure (with confirmation)
.PHONY: destroy
destroy: ## Destroy Terraform infrastructure
	@echo "Destroying Terraform infrastructure..."
	cd $(TERRAFORM_DIR) && terraform destroy

# Destroy Terraform infrastructure (auto-approve)
.PHONY: destroy-auto
destroy-auto: ## Destroy Terraform infrastructure without confirmation
	@echo "Destroying Terraform infrastructure (auto-approve)..."
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

# Show Terraform outputs
.PHONY: output
output: ## Show Terraform outputs
	@echo "Showing Terraform outputs..."
	cd $(TERRAFORM_DIR) && terraform output

# Clean Terraform state and cache
.PHONY: clean
clean: ## Clean Terraform state and cache files
	@echo "Cleaning Terraform files..."
	find $(TERRAFORM_DIR) -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find $(TERRAFORM_DIR) -name "terraform.tfstate*" -type f -delete 2>/dev/null || true
	find $(TERRAFORM_DIR) -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true

# Run all tests (comprehensive test suite)
.PHONY: test
test: init validate fmt checkov ## Run comprehensive test suite
	@echo "All tests completed successfully!"

# Quick test (without Checkov for faster feedback)
.PHONY: test-quick
test-quick: init validate fmt ## Run quick tests
	@echo "Quick tests completed successfully!"

# Pre-commit checks
.PHONY: pre-commit
pre-commit: fmt-check validate checkov ## Run pre-commit checks
	@echo "Pre-commit checks completed successfully!"

# Install dependencies (requires system package manager)
.PHONY: install-deps
install-deps: ## Install required dependencies
	@echo "Installing dependencies..."
	@echo "Please ensure you have the following tools installed:"
	@echo "- Terraform >= 1.0"
	@echo "- Checkov (pip install checkov)"
	@echo "- AWS CLI configured with appropriate permissions"

# Show Terraform version
.PHONY: version
version: ## Show Terraform version
	@echo "Terraform version:"
	terraform version

# Show workspace information
.PHONY: workspace
workspace: ## Show current Terraform workspace
	@echo "Current Terraform workspace:"
	cd $(TERRAFORM_DIR) && terraform workspace show

# Refresh Terraform state
.PHONY: refresh
refresh: ## Refresh Terraform state
	@echo "Refreshing Terraform state..."
	cd $(TERRAFORM_DIR) && terraform refresh

# Show Terraform state list
.PHONY: state-list
state-list: ## List resources in Terraform state
	@echo "Resources in Terraform state:"
	cd $(TERRAFORM_DIR) && terraform state list

# Show detailed resource information
.PHONY: state-show
state-show: ## Show detailed resource information (requires RESOURCE parameter)
	@echo "Showing detailed resource information..."
	@if [ -z "$(RESOURCE)" ]; then \
		echo "Please specify RESOURCE parameter: make state-show RESOURCE=<resource_address>"; \
		cd $(TERRAFORM_DIR) && terraform state list; \
	else \
		cd $(TERRAFORM_DIR) && terraform state show $(RESOURCE); \
	fi

# Import existing resource
.PHONY: import
import: ## Import existing resource (requires RESOURCE and ID parameters)
	@echo "Importing existing resource..."
	@if [ -z "$(RESOURCE)" ] || [ -z "$(ID)" ]; then \
		echo "Please specify both RESOURCE and ID parameters:"; \
		echo "make import RESOURCE=<resource_address> ID=<resource_id>"; \
	else \
		cd $(TERRAFORM_DIR) && terraform import $(RESOURCE) $(ID); \
	fi

.PHONY: clean
clean: ## Remove all Terraform and Terragrunt cache and ephemeral files
    @echo "Cleaning Terraform and Terragrunt cache files..."
    @find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    @find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
    @find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
    @find . -type f -name "*.tfstate" -delete 2>/dev/null || true
    @find . -type f -name "*.tfstate.backup" -delete 2>/dev/null || true
    @find . -type f -name "*.tfplan" -delete 2>/dev/null || true
    @find . -type f -name "crash.log" -delete 2>/dev/null || true
    @echo "Clean complete!"