#!/usr/bin/env bash
# =============================================================================
# Region Configuration Checker
# =============================================================================
# This script validates that all AWS region configurations are consistent
# across environment variables, AWS CLI config, and Terraform variables.
#
# Run this before deployment to catch region mismatches early.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "AWS Region Configuration Checker"
echo "========================================"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [[ $status == "OK" ]]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [[ $status == "WARN" ]]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Track overall status
all_regions=()
has_error=false

# 1. Check AWS_REGION environment variable
echo "1. Checking AWS_REGION environment variable..."
if [[ -n "$AWS_REGION" ]]; then
    print_status "OK" "AWS_REGION=$AWS_REGION"
    all_regions+=("$AWS_REGION")
else
    print_status "ERROR" "AWS_REGION is not set!"
    has_error=true
fi
echo ""

# 2. Check TF_STATE_REGION environment variable
echo "2. Checking TF_STATE_REGION environment variable..."
if [[ -n "$TF_STATE_REGION" ]]; then
    print_status "OK" "TF_STATE_REGION=$TF_STATE_REGION"
    all_regions+=("$TF_STATE_REGION")
else
    print_status "WARN" "TF_STATE_REGION not set (will default to AWS_REGION)"
fi
echo ""

# 3. Check AWS CLI config
echo "3. Checking AWS CLI configuration..."
cli_region=$(aws configure get region 2>/dev/null || echo "")
if [[ -n "$cli_region" ]]; then
    print_status "OK" "AWS CLI default region=$cli_region"
    all_regions+=("$cli_region")
else
    print_status "WARN" "AWS CLI default region not configured"
fi
echo ""

# 4. Check base layer terraform.tfvars
echo "4. Checking base layer terraform.tfvars..."
if [[ -f "base/terraform.tfvars" ]]; then
    base_region=$(grep -E '^\s*aws_region\s*=' base/terraform.tfvars | sed -E 's/.*=\s*"([^"]+)".*/\1/' || echo "")
    if [[ -n "$base_region" ]]; then
        print_status "OK" "base/terraform.tfvars: aws_region=$base_region"
        all_regions+=("$base_region")
    else
        print_status "WARN" "base/terraform.tfvars: aws_region not found"
    fi
else
    print_status "ERROR" "base/terraform.tfvars not found!"
    has_error=true
fi
echo ""

# 5. Check middleware layer terraform.tfvars
echo "5. Checking middleware layer terraform.tfvars..."
if [[ -f "middleware/terraform.tfvars" ]]; then
    middleware_region=$(grep -E '^\s*aws_region\s*=' middleware/terraform.tfvars | sed -E 's/.*=\s*"([^"]+)".*/\1/' || echo "")
    if [[ -n "$middleware_region" ]]; then
        print_status "OK" "middleware/terraform.tfvars: aws_region=$middleware_region"
        all_regions+=("$middleware_region")
    else
        print_status "WARN" "middleware/terraform.tfvars: aws_region not found"
    fi
else
    print_status "ERROR" "middleware/terraform.tfvars not found!"
    has_error=true
fi
echo ""

# 6. Check application layer terraform.tfvars
echo "6. Checking application layer terraform.tfvars..."
if [[ -f "application/terraform.tfvars" ]]; then
    app_region=$(grep -E '^\s*aws_region\s*=' application/terraform.tfvars | sed -E 's/.*=\s*"([^"]+)".*/\1/' || echo "")
    if [[ -n "$app_region" ]]; then
        print_status "OK" "application/terraform.tfvars: aws_region=$app_region"
        all_regions+=("$app_region")
    else
        print_status "WARN" "application/terraform.tfvars: aws_region not found"
    fi
else
    print_status "ERROR" "application/terraform.tfvars not found!"
    has_error=true
fi
echo ""

# Final consistency check
echo "========================================"
echo "Consistency Check"
echo "========================================"

# Remove empty entries and get unique regions
unique_regions=($(printf '%s\n' "${all_regions[@]}" | sort -u))

if [[ ${#unique_regions[@]} -eq 0 ]]; then
    print_status "ERROR" "No regions found in any configuration!"
    has_error=true
elif [[ ${#unique_regions[@]} -eq 1 ]]; then
    print_status "OK" "All configurations use the same region: ${unique_regions[0]}"
    echo ""
    echo -e "${GREEN}✓ Region configuration is consistent!${NC}"
    echo ""
    echo "You can proceed with deployment."
else
    print_status "ERROR" "Found ${#unique_regions[@]} different regions:"
    for region in "${unique_regions[@]}"; do
        echo "  - $region"
    done
    has_error=true
fi

echo ""

if [[ $has_error == true ]]; then
    echo -e "${RED}❌ Region configuration has errors!${NC}"
    echo ""
    echo "To fix this:"
    echo "1. Set AWS_REGION environment variable: export AWS_REGION='us-west-2'"
    echo "2. Set TF_STATE_REGION environment variable: export TF_STATE_REGION='us-west-2'"
    echo "3. Update AWS CLI config: aws configure set region us-west-2"
    echo "4. Verify terraform.tfvars in all layers have matching aws_region values"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    exit 0
fi
