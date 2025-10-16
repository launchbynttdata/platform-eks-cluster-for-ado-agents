#!/bin/bash

# EKS Cluster Deployment Script
# Handles the two-stage deployment to avoid circular dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting EKS Cluster Deployment${NC}"

# Stage 1: Deploy cluster without aws-auth management
echo -e "${YELLOW}Stage 1: Deploying EKS cluster (without aws-auth management)...${NC}"
terraform plan -var="enable_kube_auth_management=false" -out=cluster.tfplan
terraform apply -auto-approve cluster.tfplan

# Wait for cluster to be fully ready
echo -e "${YELLOW}Waiting for cluster to be fully ready...${NC}"
sleep 30

# Update kubeconfig to ensure connectivity
echo -e "${YELLOW}Updating kubeconfig...${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region $(aws configure get region) --name $CLUSTER_NAME

# Verify cluster connectivity
echo -e "${YELLOW}Verifying cluster connectivity...${NC}"
kubectl get nodes || {
    echo -e "${RED}Failed to connect to cluster. Please check your AWS credentials and cluster status.${NC}"
    exit 1
}

# Stage 2: Enable aws-auth management and apply
echo -e "${YELLOW}Stage 2: Enabling aws-auth ConfigMap management...${NC}"
terraform plan -var="enable_kube_auth_management=true" -out=auth.tfplan
terraform apply -auto-approve auth.tfplan

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}Your EKS cluster is ready with proper authentication configured.${NC}"
