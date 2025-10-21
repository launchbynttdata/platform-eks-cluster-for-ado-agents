# Testing Guide for Deploy Script

This document describes the testing strategy and tools for the infrastructure deployment automation.

## Overview

The `deploy.sh` script is now supported by two types of automated testing:

1. **Static Analysis** - ShellCheck catches common shell scripting bugs
2. **Unit Testing** - BATS provides automated test coverage for functions

## Quick Start

### Run All Tests

```bash
cd infrastructure-layered
make test
```

This will:
- ✅ Run ShellCheck static analysis
- ✅ Run BATS unit tests
- ✅ Report any failures with details

### Run Individual Test Suites

```bash
# Static analysis only
make shellcheck

# Unit tests only
make bats-test
```

## Static Analysis with ShellCheck

### What is ShellCheck?

ShellCheck is an industry-standard static analysis tool for shell scripts. It catches:
- Syntax errors and portability issues
- Common logic bugs (unquoted variables, incorrect conditionals)
- Security issues (command injection, path traversal)
- Code quality problems (unused variables, incorrect exit code handling)

### Current ShellCheck Status

The deploy.sh script passes ShellCheck with some acknowledged warnings:

#### SC2155: Declare and assign separately
```bash
# Current pattern:
local cluster_name=$(detect_cluster_name_from_tf)

# Recommended pattern:
local cluster_name
cluster_name=$(detect_cluster_name_from_tf) || return 1
```

**Status**: Acknowledged. This pattern is used for readability. Consider refactoring when adding comprehensive error handling.

#### SC2162: read without -r
```bash
# Current:
read -p "Enter value: " var

# Recommended:
read -rp "Enter value: " var
```

**Status**: Low priority. Only affects user prompts where backslash handling is not critical.

#### SC2181: Check exit code directly
```bash
# Current:
some_command
if [[ $? -eq 0 ]]; then

# Recommended:
if some_command; then
```

**Status**: Team preference. Explicit `$?` checks are acceptable for readability.

### Configuration

ShellCheck configuration is in `.shellcheckrc`:
- Enables all optional checks
- Documents acknowledged warnings
- Can be customized per project needs

## Unit Testing with BATS

### What is BATS?

BATS (Bash Automated Testing System) provides TAP-compliant test framework for bash scripts. It allows:
- Isolated testing of individual functions
- Setup and teardown for test environments
- Assertions for exit codes and output
- Integration with CI/CD pipelines

### Test Structure

```
tests/
├── README.md              # Detailed testing documentation
├── test_utils.bats        # Utility function tests
└── test_validation.bats   # Validation logic tests
```

### Writing Tests

Example test structure:

```bash
#!/usr/bin/env bats

setup() {
    # Run before each test
    export TEST_VAR="value"
    source deploy.sh  # Load functions
}

teardown() {
    # Run after each test
    unset TEST_VAR
}

@test "function does X when given Y" {
    run my_function "arg"
    [ "$status" -eq 0 ]           # Exit code
    [ "$output" = "expected" ]    # stdout
}
```

### Test Coverage

#### Currently Covered ✅
- Version comparison logic (`version_compare`)
- Layer name validation (`validate_layer_name`)
- Layer directory resolution (`get_layer_directory`)
- Directory structure validation (`validate_layer_directory`)

#### Needs Coverage ⚠️
- Terraform operations with `-backend-config`
- kubectl configuration and connectivity
- Cluster autoscaler deployment
- ESO ClusterSecretStore creation
- Error recovery and rollback
- Dry-run mode verification

### Running Specific Tests

```bash
# Run all tests
bats tests/

# Run specific file
bats tests/test_utils.bats

# Run with verbose output
bats -t tests/test_utils.bats

# Run specific test by name
bats -f "version_compare" tests/test_utils.bats
```

## Testing Best Practices

### 1. Test Isolation
- Each test should be independent
- Use `setup()` and `teardown()` to manage state
- Don't rely on execution order

### 2. Mock External Dependencies
- Use `DRY_RUN="true"` to skip AWS/kubectl operations
- Create stub functions for external commands
- Use fixtures for terraform/kubectl output

### 3. Test Edge Cases
- Empty inputs
- Invalid inputs
- Missing files/directories
- Permission errors
- Network timeouts

### 4. Descriptive Test Names
```bash
# Good
@test "terraform_init: fails when backend config missing"

# Bad
@test "init test"
```

### 5. Clear Assertions
```bash
# Check exit code
[ "$status" -eq 0 ]

# Check output
[[ "$output" =~ "expected pattern" ]]

# Check files
[ -f "$expected_file" ]
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test Deploy Script

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install ShellCheck
        run: sudo apt-get install -y shellcheck
      
      - name: Install BATS
        run: |
          git clone https://github.com/bats-core/bats-core.git
          cd bats-core
          sudo ./install.sh /usr/local
      
      - name: Run Tests
        run: |
          cd infrastructure-layered
          make test
```

## Troubleshooting

### BATS Tests Fail

1. **Check sourcing**: Ensure `setup()` correctly loads deploy.sh functions
2. **Environment variables**: Verify required vars are set in `setup()`
3. **Path issues**: Use absolute paths or `$BATS_TEST_DIRNAME`

### ShellCheck False Positives

Add directives to suppress specific warnings:

```bash
# shellcheck disable=SC2155
local var=$(command)
```

Or globally in `.shellcheckrc`:

```
disable=SC2155
```

### Tests Pass Locally But Fail in CI

- Check shell differences (bash version, macOS vs Linux)
- Verify all dependencies are installed in CI
- Use portable commands (avoid BSD vs GNU differences)

## Future Improvements

### Short Term
- [ ] Add more unit tests for terraform functions
- [ ] Create integration tests for full deployment flow
- [ ] Add test coverage reporting

### Medium Term
- [ ] Mock AWS CLI responses for offline testing
- [ ] Add performance benchmarks
- [ ] Set up pre-commit hooks for tests

### Long Term
- [ ] Contract tests for terraform module interfaces
- [ ] Chaos testing for error recovery
- [ ] Load testing for parallel operations

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Bash Testing Guide](https://github.com/sstephenson/bats/wiki/Bash-Testing-Guide)
- [Test Anything Protocol (TAP)](https://testanything.org/)

## Contributing

When adding new functions to deploy.sh:

1. ✅ Write tests first (TDD approach)
2. ✅ Run `make test` before committing
3. ✅ Update test documentation
4. ✅ Add examples for complex functions
5. ✅ Consider edge cases and error conditions
