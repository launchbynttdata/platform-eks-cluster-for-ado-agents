# Unit Tests for deploy.sh

This directory contains automated tests for the infrastructure deployment script.

## Test Framework

We use **BATS** (Bash Automated Testing System) for unit and integration testing of shell scripts.

## Running Tests

### Run all tests
```bash
cd infrastructure-layered
make test
```

### Run specific test file
```bash
bats tests/test_utils.bats
bats tests/test_validation.bats
```

### Run tests with verbose output
```bash
bats -t tests/test_utils.bats
```

## Test Structure

- `test_utils.bats` - Unit tests for utility functions (version comparison, layer validation, etc.)
- `test_validation.bats` - Integration tests for deployment validation logic
- (Future) `test_terraform.bats` - Tests for Terraform wrapper functions
- (Future) `test_kubectl.bats` - Tests for kubectl configuration and cluster interaction

## Writing New Tests

### Basic Test Structure
```bash
#!/usr/bin/env bats

setup() {
    # Run before each test
    export TEST_VAR="value"
}

teardown() {
    # Run after each test
    unset TEST_VAR
}

@test "descriptive test name" {
    run my_function "arg1"
    [ "$status" -eq 0 ]
    [ "$output" = "expected output" ]
}
```

### Test Assertions

BATS uses standard shell exit codes and comparison operators:

- `[ "$status" -eq 0 ]` - Command succeeded
- `[ "$status" -ne 0 ]` - Command failed
- `[ "$output" = "text" ]` - Exact match
- `[[ "$output" =~ pattern ]]` - Regex match
- `[ -f "$file" ]` - File exists
- `[ -d "$dir" ]` - Directory exists

## Static Analysis

### ShellCheck

We use ShellCheck for static analysis to catch common shell scripting errors:

```bash
# Run shellcheck
make shellcheck

# Or directly
shellcheck -x deploy.sh
```

### Current ShellCheck Findings

The script currently has some ShellCheck warnings:

1. **SC2155** - Declare and assign separately to avoid masking return values
   - Impact: Medium - Can hide command failures
   - Status: Acknowledged, will address in future refactoring

2. **SC2162** - read without -r will mangle backslashes
   - Impact: Low - Only affects user input prompts
   - Status: Acceptable for current use case

3. **SC2181** - Check exit code directly instead of using $?
   - Impact: Low - Style preference
   - Status: Team preference for explicit $? checks

## Test Coverage

### Currently Tested
- ✅ Version comparison logic
- ✅ Layer name validation
- ✅ Layer directory validation
- ✅ Skipped layer calculation
- ✅ Directory structure validation

### Needs Testing
- ⚠️ Terraform initialization with backend config
- ⚠️ kubectl configuration and cluster connectivity
- ⚠️ Cluster autoscaler deployment
- ⚠️ ESO ClusterSecretStore creation
- ⚠️ Error recovery and rollback logic
- ⚠️ Dry-run mode verification

## Mocking Strategy

For tests that require external dependencies (AWS CLI, kubectl, terraform):

1. Use DRY_RUN="true" to skip actual operations
2. Create stub commands in BATS setup
3. Use BATS support libraries (bats-support, bats-assert) for better assertions
4. Mock terraform/kubectl output in test fixtures

## Continuous Integration

Consider adding these tests to CI/CD pipeline:

```yaml
# Example GitHub Actions workflow
- name: Run ShellCheck
  run: make shellcheck

- name: Run BATS Tests
  run: make test
```

## Adding More Tests

To expand test coverage:

1. **Identify critical functions** - Focus on functions with complex logic
2. **Create test file** - Use naming convention `test_<category>.bats`
3. **Write test cases** - Cover happy path, edge cases, and error conditions
4. **Update this README** - Document what's tested and what needs testing

## References

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Bash Testing Best Practices](https://github.com/sstephenson/bats/wiki/Bash-Testing-Guide)
