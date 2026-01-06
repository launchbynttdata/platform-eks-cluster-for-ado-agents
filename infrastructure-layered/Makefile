# Makefile for infrastructure-layered deployment automation
# 
# This Makefile provides targets for testing and validating the deploy.sh script.

.PHONY: help shellcheck bats-test checkov test clean

# Default target
help:
	@echo "Available targets:"
	@echo "  shellcheck  - Run ShellCheck static analysis on deploy.sh"
	@echo "  bats-test   - Run BATS unit tests"
	@echo "  checkov     - Run Checkov security scan on all Terraform layers"
	@echo "  test        - Run all tests (shellcheck + unit tests + checkov)"
	@echo "  clean       - Clean up temporary test files"

# Run ShellCheck static analysis
shellcheck:
	@echo "Running ShellCheck static analysis..."
	@shellcheck -x deploy.sh || (echo "❌ ShellCheck found issues. See output above." && exit 1)
	@echo "✅ ShellCheck passed!"

# Run BATS unit tests
bats-test:
	@echo "Running BATS unit tests..."
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/ || (echo "❌ BATS tests failed. See output above." && exit 1); \
		echo "✅ BATS tests passed!"; \
	else \
		echo "⚠️  BATS not installed. Install with: brew install bats-core"; \
		exit 1; \
	fi

# Run Checkov security scan on all Terraform layers
# Note: Severity filtering (MEDIUM+) requires a Prisma Cloud API key
# Without an API key, this runs all checks and fails on any issues
checkov:
	@echo "Running Checkov security scan on Terraform configurations..."
	@echo "Note: Running all security checks including Kubernetes resources"
	@if command -v checkov >/dev/null 2>&1; then \
		echo ""; \
		echo "Scanning base layer..."; \
		checkov -d base --framework terraform --compact || exit 1; \
		echo ""; \
		echo "Scanning middleware layer..."; \
		checkov -d middleware --framework terraform --compact || exit 1; \
		echo ""; \
		echo "Scanning application layer..."; \
		checkov -d application --framework terraform --compact || exit 1; \
		echo ""; \
		echo "✅ Checkov scan passed! No security issues found."; \
	else \
		echo "⚠️  Checkov not installed. Install with: pip install checkov"; \
		exit 1; \
	fi

# Run all tests
test: shellcheck bats-test checkov
	@echo "✅ All tests passed!"

# Clean up temporary files
clean:
	@echo "Cleaning up temporary test files..."
	@rm -f /tmp/check_unused_functions.sh
	@echo "✅ Clean complete!"
