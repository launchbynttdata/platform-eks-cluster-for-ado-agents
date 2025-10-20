#!/bin/bash

# Cluster Autoscaler Validation Script
# This script validates the cluster autoscaler configuration and deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Cluster Autoscaler Validation Script                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

VALIDATION_PASSED=true

# Function to print section headers
print_section() {
    echo -e "\n${BLUE}═══ $1 ═══${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to print error
print_error() {
    echo -e "${RED}✗${NC} $1"
    VALIDATION_PASSED=false
}

# 1. Check AWS Credentials
print_section "1. AWS Credentials"
if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-west-2")
    print_success "AWS credentials valid (Account: $ACCOUNT_ID, Region: $AWS_REGION)"
else
    print_error "AWS credentials not configured or expired"
fi

# 2. Check Kubectl Configuration
print_section "2. Kubernetes Configuration"
if kubectl cluster-info &>/dev/null; then
    CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
    print_success "kubectl configured (Context: $(kubectl config current-context))"
else
    print_error "kubectl not configured properly"
fi

# 3. Check IAM Role for Cluster Autoscaler
print_section "3. IAM Role Configuration"
ROLE_NAME="poc-ado-agent-cluster-cluster-autoscaler-role"  # Update if your cluster name is different
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    print_success "IAM role exists: $ROLE_ARN"
    
    # Check if role has the correct trust policy for IRSA
    TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json)
    if echo "$TRUST_POLICY" | grep -q "system:serviceaccount:kube-system:cluster-autoscaler"; then
        print_success "IRSA trust policy configured correctly"
    else
        print_warning "Trust policy may not be configured for cluster-autoscaler service account"
    fi
    
    # Check attached policies
    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyName' --output text)
    if [[ -n "$POLICIES" ]]; then
        print_success "Attached policies: $POLICIES"
    else
        print_warning "No policies attached to the role"
    fi
else
    print_error "IAM role not found: $ROLE_NAME"
    print_warning "Run 'terraform apply' in infrastructure-layered/base/ to create the role"
fi

# 4. Check Node Groups and Auto Scaling Groups
print_section "4. Node Groups Configuration"
if command -v aws &>/dev/null && [[ -n "$CLUSTER_NAME" ]]; then
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output json 2>/dev/null || echo "[]")
    
    if [[ "$NODE_GROUPS" != "[]" ]]; then
        print_success "Found node groups: $(echo $NODE_GROUPS | jq -r '.[]' | tr '\n' ' ')"
        
        # Check each node group for cluster autoscaler tags
        for NG in $(echo $NODE_GROUPS | jq -r '.[]'); do
            echo -e "\n  ${YELLOW}Checking node group: $NG${NC}"
            NG_INFO=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NG" --output json)
            
            MIN_SIZE=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.minSize')
            MAX_SIZE=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.maxSize')
            DESIRED_SIZE=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
            
            echo "    Min: $MIN_SIZE, Max: $MAX_SIZE, Desired: $DESIRED_SIZE"
            
            # Check for cluster autoscaler tags
            AUTOSCALER_ENABLED=$(echo "$NG_INFO" | jq -r '.nodegroup.tags["k8s.io/cluster-autoscaler/enabled"] // "false"')
            AUTOSCALER_OWNED=$(echo "$NG_INFO" | jq -r --arg cn "$CLUSTER_NAME" '.nodegroup.tags["k8s.io/cluster-autoscaler/\($cn)"] // "false"')
            
            if [[ "$AUTOSCALER_ENABLED" == "true" ]]; then
                print_success "  Cluster autoscaler tag enabled"
            else
                print_warning "  Cluster autoscaler tag not enabled (k8s.io/cluster-autoscaler/enabled)"
            fi
            
            if [[ "$AUTOSCALER_OWNED" == "owned" ]]; then
                print_success "  Cluster ownership tag set"
            else
                print_warning "  Cluster ownership tag not set (k8s.io/cluster-autoscaler/$CLUSTER_NAME)"
            fi
        done
    else
        print_warning "No node groups found"
    fi
fi

# 5. Check Current Nodes
print_section "5. Current Cluster Nodes"
if kubectl get nodes &>/dev/null; then
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    print_success "Total nodes: $NODE_COUNT"
    
    echo ""
    kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,NODEGROUP:.metadata.labels.eks\\.amazonaws\\.com/nodegroup,WORKLOAD:.metadata.labels.workload-type --no-headers | while read line; do
        echo "    $line"
    done
fi

# 6. Check if Cluster Autoscaler is Deployed
print_section "6. Cluster Autoscaler Deployment"
if kubectl get deployment cluster-autoscaler -n kube-system &>/dev/null; then
    REPLICAS=$(kubectl get deployment cluster-autoscaler -n kube-system -o jsonpath='{.status.replicas}')
    READY_REPLICAS=$(kubectl get deployment cluster-autoscaler -n kube-system -o jsonpath='{.status.readyReplicas}')
    
    if [[ "$REPLICAS" == "$READY_REPLICAS" ]] && [[ "$READY_REPLICAS" -gt 0 ]]; then
        print_success "Cluster autoscaler is deployed and running ($READY_REPLICAS/$REPLICAS ready)"
        
        # Check service account annotation
        SA_ANNOTATION=$(kubectl get serviceaccount cluster-autoscaler -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
        if [[ -n "$SA_ANNOTATION" ]]; then
            print_success "Service account has IRSA annotation: $SA_ANNOTATION"
        else
            print_warning "Service account missing IRSA annotation"
        fi
        
        # Check recent logs for errors
        echo -e "\n  ${YELLOW}Recent logs (last 10 lines):${NC}"
        kubectl logs -n kube-system deployment/cluster-autoscaler --tail=10 2>/dev/null | sed 's/^/    /'
        
    else
        print_warning "Cluster autoscaler deployment exists but pods not ready ($READY_REPLICAS/$REPLICAS)"
    fi
else
    print_warning "Cluster autoscaler is NOT deployed"
    echo -e "    ${YELLOW}To deploy cluster autoscaler, you need to:${NC}"
    echo -e "    1. Ensure base layer has enable_cluster_autoscaler = true"
    echo -e "    2. Create a Kubernetes deployment for cluster-autoscaler"
    echo -e "    3. Reference documentation: docs/CLUSTER_AUTOSCALER_README.md"
fi

# 7. Test Auto Scaling Capability
print_section "7. Auto Scaling Capability Test"
if kubectl get deployment cluster-autoscaler -n kube-system &>/dev/null; then
    echo -e "  ${YELLOW}To test autoscaling:${NC}"
    echo -e "    1. Create a deployment with many replicas that won't fit on current nodes"
    echo -e "    2. Watch cluster autoscaler logs: kubectl logs -n kube-system deployment/cluster-autoscaler -f"
    echo -e "    3. Watch nodes scale up: kubectl get nodes -w"
    echo -e ""
    echo -e "  ${YELLOW}Example test command:${NC}"
    echo -e "    kubectl create deployment autoscale-test --image=nginx --replicas=10"
    echo -e "    kubectl scale deployment autoscale-test --replicas=0  # cleanup"
else
    print_warning "Deploy cluster autoscaler first to test autoscaling"
fi

# 8. Check for Fargate Profiles (should not conflict)
print_section "8. Fargate Profile Check"
if command -v aws &>/dev/null && [[ -n "$CLUSTER_NAME" ]]; then
    FARGATE_PROFILES=$(aws eks list-fargate-profiles --cluster-name "$CLUSTER_NAME" --query 'fargateProfileNames' --output json 2>/dev/null || echo "[]")
    
    if [[ "$FARGATE_PROFILES" != "[]" ]]; then
        print_success "Fargate profiles exist (mixed EC2+Fargate cluster)"
        echo "    Profiles: $(echo $FARGATE_PROFILES | jq -r '.[]' | tr '\n' ' ')"
        print_success "Cluster autoscaler will only manage EC2 node groups"
    else
        print_success "No Fargate profiles (EC2-only cluster)"
    fi
fi

# Summary
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
if $VALIDATION_PASSED; then
    echo -e "${GREEN}✓ Validation completed successfully!${NC}"
    
    if ! kubectl get deployment cluster-autoscaler -n kube-system &>/dev/null; then
        echo -e "\n${YELLOW}Next Steps:${NC}"
        echo -e "  1. Deploy cluster autoscaler using kubectl or Helm"
        echo -e "  2. See docs/CLUSTER_AUTOSCALER_README.md for deployment instructions"
    fi
else
    echo -e "${RED}✗ Validation found issues that need attention${NC}"
    echo -e "${YELLOW}Review the errors above and fix them before deploying cluster autoscaler${NC}"
fi
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

exit $([ "$VALIDATION_PASSED" = true ] && echo 0 || echo 1)
