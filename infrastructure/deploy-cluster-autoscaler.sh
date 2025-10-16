#!/bin/bash

# Deploy Cluster Autoscaler with values from Terraform outputs
# This script should be run after terraform apply completes successfully

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Cluster Autoscaler Deployment Script ===${NC}"

# Check if terraform outputs are available
echo -e "${YELLOW}Checking Terraform outputs...${NC}"

# Get values from terraform output
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
CLUSTER_AUTOSCALER_ROLE_ARN=$(terraform output -raw cluster_autoscaler_role_arn 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || aws configure get region)
CLUSTER_AUTOSCALER_VERSION=$(terraform output -raw cluster_autoscaler_version 2>/dev/null || echo "v1.29.0")
CLUSTER_AUTOSCALER_ENABLED=$(terraform output -raw cluster_autoscaler_enabled 2>/dev/null || echo "false")

# Validate required values
if [[ -z "$CLUSTER_NAME" ]]; then
    echo -e "${RED}Error: Could not get cluster_name from terraform output${NC}"
    exit 1
fi

if [[ "$CLUSTER_AUTOSCALER_ENABLED" != "true" ]]; then
    echo -e "${YELLOW}Cluster Autoscaler is not enabled. Set enable_cluster_autoscaler = true in terraform.tfvars${NC}"
    exit 0
fi

if [[ -z "$CLUSTER_AUTOSCALER_ROLE_ARN" ]] || [[ "$CLUSTER_AUTOSCALER_ROLE_ARN" == "null" ]]; then
    echo -e "${RED}Error: Could not get cluster_autoscaler_role_arn from terraform output${NC}"
    echo -e "${YELLOW}Make sure you have run terraform apply with enable_cluster_autoscaler = true${NC}"
    exit 1
fi

if [[ -z "$AWS_REGION" ]]; then
    echo -e "${RED}Error: Could not determine AWS region${NC}"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Role ARN: $CLUSTER_AUTOSCALER_ROLE_ARN"
echo "  AWS Region: $AWS_REGION"
echo "  Autoscaler Version: $CLUSTER_AUTOSCALER_VERSION"

# Check if kubectl is configured for the cluster
echo -e "${YELLOW}Checking kubectl configuration...${NC}"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ -z "$CURRENT_CONTEXT" ]]; then
    echo -e "${RED}Error: kubectl is not configured. Run 'aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME'${NC}"
    exit 1
fi

# Backup existing deployment if it exists
if kubectl get deployment cluster-autoscaler -n kube-system &>/dev/null; then
    echo -e "${YELLOW}Backing up existing cluster-autoscaler deployment...${NC}"
    kubectl get deployment cluster-autoscaler -n kube-system -o yaml > cluster-autoscaler-backup-$(date +%Y%m%d-%H%M%S).yaml
fi

# Create a temporary file with the replaced values
TEMP_FILE=$(mktemp)
cp app/k8s/cluster-autoscaler.yaml "$TEMP_FILE"

# Replace placeholder values
sed -i.bak "s|REPLACE_WITH_CLUSTER_AUTOSCALER_ROLE_ARN|$CLUSTER_AUTOSCALER_ROLE_ARN|g" "$TEMP_FILE"
sed -i.bak "s|REPLACE_WITH_CLUSTER_NAME|$CLUSTER_NAME|g" "$TEMP_FILE"
sed -i.bak "s|REPLACE_WITH_AWS_REGION|$AWS_REGION|g" "$TEMP_FILE"
sed -i.bak "s|REPLACE_WITH_AUTOSCALER_VERSION|$CLUSTER_AUTOSCALER_VERSION|g" "$TEMP_FILE"

# Apply the cluster autoscaler
echo -e "${YELLOW}Deploying Cluster Autoscaler...${NC}"
kubectl apply -f "$TEMP_FILE"

# Clean up
rm "$TEMP_FILE" "$TEMP_FILE.bak"

# Wait for deployment to be ready
echo -e "${YELLOW}Waiting for Cluster Autoscaler to be ready...${NC}"
kubectl rollout status deployment/cluster-autoscaler -n kube-system --timeout=300s

# Check the logs
echo -e "${GREEN}Cluster Autoscaler deployed successfully!${NC}"
echo -e "${YELLOW}Checking Cluster Autoscaler logs:${NC}"
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=20

echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo -e "${YELLOW}To monitor the Cluster Autoscaler:${NC}"
echo "  kubectl logs -n kube-system deployment/cluster-autoscaler --follow"
echo ""
echo -e "${YELLOW}To test autoscaling, scale your buildkit deployment:${NC}"
echo "  kubectl scale deployment buildkitd --replicas=5 -n build"