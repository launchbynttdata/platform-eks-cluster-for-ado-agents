#!/bin/bash

# External Secrets Operator Validation Script
# This script validates that ESO is properly installed and has access to secrets

set -e

echo "🔍 External Secrets Operator Validation Script"
echo "=============================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper to read terraform outputs without failing the script when terraform state is unavailable
tf_output_or_empty() {
    local name=$1
    terraform output -raw "$name" 2>/dev/null || true
}

# Resolve secret names dynamically, allowing overrides via environment variables
ADO_PAT_SECRET_NAME=${ADO_PAT_SECRET_NAME:-$(tf_output_or_empty ado_pat_secret_name)}
if [ -z "$ADO_PAT_SECRET_NAME" ]; then
    ADO_PAT_SECRET_NAME="ado-agent-pat"
fi

ADO_SECRET_NAME=${ADO_SECRET_NAME:-$(tf_output_or_empty ado_secret_name)}
if [ -z "$ADO_SECRET_NAME" ]; then
    ADO_SECRET_NAME="$ADO_PAT_SECRET_NAME"
fi

ADO_EXTERNAL_SECRET_NAME=${ADO_EXTERNAL_SECRET_NAME:-${ADO_SECRET_NAME}-secret}

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗${NC} $message"
        return 1
    elif [ "$status" = "INFO" ]; then
        echo -e "${YELLOW}ℹ${NC} $message"
    fi
}

# Check if kubectl is available and cluster is accessible
check_cluster_access() {
    print_status "INFO" "Checking cluster access..."
    
    if ! command -v kubectl &> /dev/null; then
        print_status "FAIL" "kubectl is not installed or not in PATH"
        return 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_status "FAIL" "Cannot connect to Kubernetes cluster"
        return 1
    fi

    local cluster_name=$(kubectl config current-context)
    print_status "OK" "Connected to cluster: $cluster_name"
}

# Check if External Secrets Operator namespace exists
check_eso_namespace() {
    print_status "INFO" "Checking External Secrets Operator namespace..."
    
    if kubectl get namespace external-secrets-system &> /dev/null; then
        print_status "OK" "External Secrets Operator namespace exists"
    else
        print_status "FAIL" "External Secrets Operator namespace not found"
        return 1
    fi
}

# Check External Secrets Operator pods
check_eso_pods() {
    print_status "INFO" "Checking External Secrets Operator pods..."
    
    local pods=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$pods" ]; then
        print_status "FAIL" "No External Secrets Operator pods found"
        return 1
    fi

    print_status "OK" "External Secrets Operator pods found: $pods"

    # Check pod status
    local ready_pods=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$ready_pods" ]; then
        print_status "FAIL" "External Secrets Operator pods are not running"
        kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets
        return 1
    fi

    print_status "OK" "External Secrets Operator pods are running"
}

# Check External Secrets Operator service account
check_eso_service_account() {
    print_status "INFO" "Checking External Secrets Operator service account..."
    
    if kubectl get serviceaccount external-secrets -n external-secrets-system &> /dev/null; then
        print_status "OK" "External Secrets service account exists"
        
        # Check for IRSA annotation
        local role_arn=$(kubectl get serviceaccount external-secrets -n external-secrets-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
        
        if [ -n "$role_arn" ]; then
            print_status "OK" "Service account has IRSA annotation: $role_arn"
        else
            print_status "FAIL" "Service account missing IRSA annotation"
            return 1
        fi
    else
        print_status "FAIL" "External Secrets service account not found"
        return 1
    fi
}

# Check ClusterSecretStore
check_cluster_secret_store() {
    print_status "INFO" "Checking ClusterSecretStore..."
    
    if kubectl get clustersecretstore aws-secrets-manager &> /dev/null; then
        print_status "OK" "ClusterSecretStore 'aws-secrets-manager' exists"
        
        # Check status
        local ready=$(kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        
        if [ "$ready" = "True" ]; then
            print_status "OK" "ClusterSecretStore is ready"
        else
            print_status "FAIL" "ClusterSecretStore is not ready"
            kubectl describe clustersecretstore aws-secrets-manager
            return 1
        fi
    else
        print_status "FAIL" "ClusterSecretStore 'aws-secrets-manager' not found"
        return 1
    fi
}

# Check ExternalSecret for ADO PAT
check_external_secret() {
    print_status "INFO" "Checking ExternalSecret for ADO PAT..."
    
    if kubectl get externalsecret "$ADO_EXTERNAL_SECRET_NAME" -n ado-agents &> /dev/null; then
        print_status "OK" "ExternalSecret '${ADO_EXTERNAL_SECRET_NAME}' exists in ado-agents namespace"
        
        # Check status
        local ready=$(kubectl get externalsecret "$ADO_EXTERNAL_SECRET_NAME" -n ado-agents -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        
        if [ "$ready" = "True" ]; then
            print_status "OK" "ExternalSecret is ready and syncing"
        else
            print_status "FAIL" "ExternalSecret is not ready"
            kubectl describe externalsecret "$ADO_EXTERNAL_SECRET_NAME" -n ado-agents
            return 1
        fi
    else
        print_status "FAIL" "ExternalSecret '${ADO_EXTERNAL_SECRET_NAME}' not found in ado-agents namespace"
        return 1
    fi
}

# Check if the synced Kubernetes secret exists
check_synced_secret() {
    print_status "INFO" "Checking synced Kubernetes secret..."
    
    # Get the secret name from ExternalSecret
    local secret_name=$(kubectl get externalsecret "$ADO_EXTERNAL_SECRET_NAME" -n ado-agents -o jsonpath='{.spec.target.name}')
    
    if [ -z "$secret_name" ]; then
        print_status "FAIL" "Cannot determine target secret name from ExternalSecret"
        return 1
    fi

    if kubectl get secret "$secret_name" -n ado-agents &> /dev/null; then
        print_status "OK" "Synced secret '$secret_name' exists in ado-agents namespace"
        
        # Check if secret has data
        local keys=$(kubectl get secret "$secret_name" -n ado-agents -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "")
        
        if [ -n "$keys" ]; then
            print_status "OK" "Secret contains keys: $(echo $keys | tr '\n' ' ')"
        else
            print_status "FAIL" "Secret exists but contains no data"
            return 1
        fi
    else
        print_status "FAIL" "Synced secret '$secret_name' not found"
        return 1
    fi
}

# Test AWS Secrets Manager access
test_aws_access() {
    print_status "INFO" "Testing AWS Secrets Manager access..."
    
    # Create a test pod to check access
    local test_pod_name="eso-aws-test-$(date +%s)"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $test_pod_name
  namespace: external-secrets-system
  annotations:
    iam.amazonaws.com/role: $(kubectl get serviceaccount external-secrets -n external-secrets-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
spec:
  serviceAccountName: external-secrets
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ['sleep', '300']
  restartPolicy: Never
EOF

    # Wait for pod to be ready
    kubectl wait --for=condition=Ready pod/$test_pod_name -n external-secrets-system --timeout=60s

    # Test AWS Secrets Manager access
    local secret_arn=$(kubectl exec $test_pod_name -n external-secrets-system -- aws secretsmanager describe-secret --secret-id "$ADO_PAT_SECRET_NAME" --query 'ARN' --output text 2>/dev/null || echo "")
    
    # Cleanup test pod
    kubectl delete pod $test_pod_name -n external-secrets-system --wait=false

    if [ -n "$secret_arn" ]; then
        print_status "OK" "Successfully accessed AWS Secrets Manager secret: $secret_arn"
    else
        print_status "FAIL" "Cannot access AWS Secrets Manager (check IAM permissions)"
        return 1
    fi
}

# Main validation function
main() {
    local exit_code=0

    echo
    check_cluster_access || exit_code=1

    echo
    check_eso_namespace || exit_code=1

    echo
    check_eso_pods || exit_code=1

    echo
    check_eso_service_account || exit_code=1

    echo
    check_cluster_secret_store || exit_code=1

    echo
    check_external_secret || exit_code=1

    echo
    check_synced_secret || exit_code=1

    echo
    test_aws_access || exit_code=1

    echo
    echo "=============================================="
    if [ $exit_code -eq 0 ]; then
        print_status "OK" "All External Secrets Operator validations passed!"
        echo
        echo "✅ External Secrets Operator is properly installed and configured"
        echo "✅ ClusterSecretStore is connected to AWS Secrets Manager"
        echo "✅ ExternalSecret is successfully syncing the ADO PAT"
        echo "✅ IAM permissions are correctly configured"
    else
        print_status "FAIL" "Some validations failed. Please check the output above."
        echo
        echo "🔧 Troubleshooting tips:"
        echo "   • Check pod logs: kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets"
        echo "   • Verify IAM role permissions for Secrets Manager access"
        echo "   • Ensure the ado-pat secret exists in AWS Secrets Manager"
        echo "   • Check ExternalSecret and ClusterSecretStore status with: kubectl describe"
    fi

    exit $exit_code
}

# Run main function
main "$@"
