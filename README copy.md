# Platform NTT ADO Cluster Infrastructure as Code

A Terraform-based Infrastructure as Code (IaC) solution for deploying an AWS EKS cluster with Azure DevOps (ADO) self-hosted agents. This repository provides a complete, production-ready platform for running containerized Azure DevOps agents in AWS using Kubernetes with KEDA autoscaling.

## High-Level Overview

This repository provides a comprehensive solution for deploying Azure DevOps build agents on AWS infrastructure using:

- **AWS EKS Cluster**: Managed Kubernetes cluster with Fargate and optional EC2 node groups
- **Azure DevOps Agents**: Containerized ADO agents with role-based access controls
- **KEDA Autoscaling**: Event-driven autoscaling based on Azure DevOps pipeline queue metrics
- **External Secrets**: Automatic secret synchronization from AWS Secrets Manager to Kubernetes
- **Multi-Role Architecture**: Separate IAM roles for different agent workloads (dev-build, iac, custom)
- **Secure Networking**: VPC endpoints, private subnets, encrypted communications
- **Modular Design**: Reusable Terraform modules for easy customization and maintenance

## Architecture Components

### Infrastructure Layer (Terraform)

The Terraform infrastructure is organized into a modular architecture:

```bash
infrastructure/
├── main.tf                    # Root module orchestration
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Infrastructure outputs
├── locals.tf                  # Local value computations
├── terraform.tfvars          # Environment-specific configuration
├── deploy.sh                  # Two-stage deployment script
└── modules/
    ├── collections/           # High-level module compositions
    │   ├── ado-eks-cluster/   # Main EKS cluster with ADO integration
    │   └── ecr/               # ECR repository management
    └── primitive/             # Low-level infrastructure components
        ├── eks-cluster/       # Core EKS cluster
        ├── fargate-profile/   # Fargate execution profiles
        ├── keda-operator/     # KEDA installation and configuration
        ├── external-secrets-operator/ # ESO installation
        ├── iam-roles/         # IAM role creation
        ├── security-groups/   # Network security
        ├── vpc-endpoints/     # Private AWS service access
        └── ecr-repository/    # Container registry
```

#### Key Infrastructure Features

- **EKS Cluster**: Kubernetes 1.33 with configurable public/private endpoint access
- **Fargate Profiles**: Serverless container execution for system and application workloads
- **EC2 Node Groups**: Optional managed node groups with cluster autoscaler support
- **VPC Endpoints**: Private connectivity to AWS services (ECR, Secrets Manager, CloudWatch, S3, STS)
- **IAM Integration**: IRSA (IAM Roles for Service Accounts) for secure, keyless authentication
- **Encryption**: KMS encryption for EKS secrets and ECR repositories
- **Monitoring**: CloudWatch logging and optional cluster autoscaler metrics

### Application Layer (Kubernetes + Containers)

The application layer consists of:

```bash
app/
├── ado-agent/                 # Standard ADO agent container
│   ├── Dockerfile            # Multi-arch Ubuntu-based image
│   └── start.sh              # Agent bootstrap and lifecycle script
├── ado-agent-iac/            # Infrastructure-focused ADO agent
│   ├── Dockerfile            # Extended with Terraform/AWS tools
│   └── start.sh              # IAC-specific agent bootstrap
└── k8s/                      # Kubernetes manifests
    ├── ado-agent-deployment.yaml        # Standard agent deployment
    ├── ado-iac-agent-deployment.yaml    # Infrastructure agent deployment
    ├── ado-trigger-auth.yaml            # KEDA authentication
    ├── keda-scaledobject.yaml           # Auto-scaling configuration
    ├── keda-iac-scaledobject.yaml       # IAC agent scaling
    ├── buildkit-agents.yaml             # BuildKit daemon workloads
    ├── cluster-autoscaler.yaml          # EC2 node scaling
    └── serviceaccounts.yaml             # IRSA service accounts
```

#### Container Images

Two specialized container images are provided:

1. **Standard ADO Agent** (`app/ado-agent/`):
   - Ubuntu 24.04 base with Azure DevOps agent
   - AWS CLI, build tools, container utilities
   - Multi-architecture support (amd64/arm64)
   - Designed for general build and CI/CD workloads

2. **Infrastructure ADO Agent** (`app/ado-agent-iac/`):
   - Extended with Terraform, infrastructure tools
   - Additional AWS SDK tools
   - Optimized for infrastructure-as-code deployments

### Automation and Tooling

```bash
├── Makefile                   # Development workflow automation
├── deploy.sh                  # Two-stage deployment script
└── docs/                     # Detailed documentation
    ├── CLUSTER_AUTOSCALER_README.md    # EC2 autoscaling setup
    ├── ECR_Multiple_Repositories_Example.md
    ├── EKS_AUTH_SOLUTIONS.md            # Authentication strategies
    └── OCI_IMAGE_CROSS_BUILD_README.md  # Multi-arch builds
```

## Known Issues

- Kubernetes Metrics Server is not reliably reporting for all workloads
- FARGATE profiles should be deployed as iterative list instead of singleton list
- Many IAM policies exist as "inline" that should be refactored to externally managed + attachments

## How It Works

### 1. Infrastructure Deployment

The Terraform infrastructure follows a modular, two-stage deployment process:

1. **Stage 1 - Core Infrastructure**: 
   - EKS cluster creation with networking and security
   - Fargate profiles for pod execution
   - IAM roles and OIDC provider setup
   - VPC endpoints for private AWS service access

2. **Stage 2 - Kubernetes Integration**:
   - KEDA operator installation for autoscaling
   - External Secrets Operator for secret management
   - Cluster autoscaler for EC2 nodes (if enabled)
   - ADO agent execution roles with IRSA

### 2. Role-Based Agent Architecture

The platform implements a role-based architecture where different types of Azure DevOps agents run with specific IAM permissions:

- **dev-build**: Limited ECR permissions for container builds
- **iac**: Full AWS access for infrastructure deployments
- **custom roles**: User-defined permissions for specialized workloads

Each role maps to:

- Dedicated Kubernetes ServiceAccount with IRSA annotations
- Specific ECR repositories and AWS resource access
- Separate Azure DevOps agent pools
- Independent KEDA scaling configurations

### 3. Autoscaling with KEDA

KEDA monitors Azure DevOps pipeline queues and scales agent pods based on:

- Queue depth in specific agent pools
- Configurable scaling thresholds and behaviors
- Independent scaling per agent role/pool
- Scale-to-zero during idle periods

### 4. Secret Management

External Secrets Operator automatically synchronizes:

- Azure DevOps Personal Access Tokens from AWS Secrets Manager
- Organization and URL configuration
- Kubernetes secrets accessible to agent pods
- Continuous synchronization with configurable refresh intervals

### 5. Container Image Management

ECR repositories are automatically created and configured with:

- KMS encryption for security
- Lifecycle policies for cost optimization
- Cross-architecture image support
- IAM policies for role-based access

## Dependencies

### Required Infrastructure

You must provide the following AWS infrastructure before deploying:

#### 1. VPC and Networking

- **VPC** with DNS hostnames and resolution enabled
- **Private subnets** in at least 2 availability zones
- **Route tables** configured for private subnets
- **NAT Gateway** or NAT Instance for outbound internet access
- **Internet Gateway** attached to VPC (for NAT Gateway)

#### 2. AWS Permissions

The deploying user/role needs permissions for:

- EKS cluster management
- IAM role and policy creation
- VPC endpoint creation
- ECR repository management
- Secrets Manager access
- KMS key management
- CloudWatch logging

#### 3. Required Tools

**Local Development:**

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- kubectl for cluster access
- Docker for building custom images
- make (optional, for using Makefile commands)

**Security Scanning (Optional):**

- Checkov for infrastructure security scanning

### Azure DevOps Requirements

#### 1. Organization Setup

- Azure DevOps organization with admin access
- Agent pools configured for different workload types
- Service connections to AWS (for pipeline authentication)

#### 2. Personal Access Token

A PAT with the following scopes:

- **Agent Pools**: Read & manage
- **Build**: Read & execute (for queue monitoring)
- **Project and Team**: Read (for organization access)

#### 3. Pipeline Configuration

- Azure Pipelines configured to use custom agent pools
- Build definitions targeting specific pools based on workload type

### Container Registry

#### 1. ECR Setup (Automated)

The Terraform automatically creates:

- ECR repositories for each agent type
- Lifecycle policies for image management
- IAM policies for push/pull access
- KMS encryption configuration

#### 2. Image Building (Manual)

You need to:

- Build agent container images using provided Dockerfiles
- Push images to created ECR repositories
- Tag images appropriately for different architectures

## Quick Start

### 1. Prerequisites Check

```bash
# Verify required tools
terraform version
aws --version
kubectl version --client
docker --version

# Verify AWS credentials
aws sts get-caller-identity
```

### 2. Configure Infrastructure

```bash
# Clone repository
git clone <repository-url>
cd platform-ntt-ado_cluster_iac

# Copy and customize configuration
cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars
# Edit terraform.tfvars with your VPC and organization details
```

### 3. Deploy Infrastructure

```bash
cd infrastructure

# Initialize Terraform
make init

# Review planned changes
make plan

# Deploy infrastructure
make apply
# OR use the automated two-stage deployment
./deploy.sh
```

### 4. Configure Secrets

```bash
# Set Azure DevOps PAT in AWS Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw ado_pat_secret_name)" \
  --secret-string '{
    "personalAccessToken":"your-ado-pat-here",
    "organization":"your-ado-organization", 
    "adourl":"https://dev.azure.com/your-ado-organization"
  }'
```

### 5. Build and Deploy Agents

```bash
# Build standard agent image
cd app/ado-agent
docker build -t ado-agent:latest .

# Build infrastructure agent image  
cd ../ado-agent-iac
docker build -t ado-agent-iac:latest .

# Tag and push to ECR (replace with your account/region)
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin <account>.dkr.ecr.us-west-2.amazonaws.com

docker tag ado-agent:latest <account>.dkr.ecr.us-west-2.amazonaws.com/ado-agent:latest
docker push <account>.dkr.ecr.us-west-2.amazonaws.com/ado-agent:latest
```

### 6. Deploy Kubernetes Manifests

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name your-cluster-name

# Deploy agent configurations
kubectl apply -f app/k8s/serviceaccounts.yaml
kubectl apply -f app/k8s/ado-trigger-auth.yaml
kubectl apply -f app/k8s/ado-agent-deployment.yaml
kubectl apply -f app/k8s/keda-scaledobject.yaml
```

### 7. Verify Deployment

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n keda-system
kubectl get pods -n external-secrets-system
kubectl get pods -n ado-agents

# Verify KEDA scaling
kubectl get scaledobjects -n ado-agents
kubectl describe scaledobject azure-devops-scaler -n ado-agents

# Check secret synchronization
kubectl get secret ado-pat -n ado-agents -o yaml
```

For detailed configuration options, troubleshooting, and advanced usage, see the documentation in the `docs/` directory.

## Next Steps

The following improvements would enhance the platform's capabilities, reliability, and maintainability:

### Infrastructure Enhancements

#### 1. Monitoring and Observability

- **Kubernetes Metrics Server**: Fix reliability issues and ensure proper metrics collection for all workloads
- **Prometheus + Grafana**: Add comprehensive monitoring stack for cluster and application metrics
- **CloudWatch Container Insights**: Enhanced EKS monitoring integration
- **Distributed Tracing**: Implement OpenTelemetry for pipeline and agent tracing
- **Log Aggregation**: Centralized logging with structured log formats and retention policies

#### 2. Security Hardening

- **Pod Security Standards**: Implement Kubernetes Pod Security Standards (restricted profile)
- **Network Policies**: Add Calico or native Kubernetes network policies for microsegmentation
- **Image Scanning**: Integrate container vulnerability scanning in CI/CD pipeline
- **Secret Rotation**: Automated rotation of Azure DevOps PATs and other credentials
- **OPA Gatekeeper**: Policy-as-code for cluster governance and compliance

#### 3. High Availability and Disaster Recovery

- **Multi-Region Deployment**: Support for deploying across multiple AWS regions
- **Backup Strategy**: Automated backup of cluster configurations and persistent data
- **Cross-AZ Resilience**: Ensure workloads can survive availability zone failures
- **Blue-Green Deployments**: Support for zero-downtime cluster upgrades

### Architecture Improvements

#### 4. Fargate Profile Optimization

- **Iterative Deployment**: Refactor Fargate profiles from singleton to iterative list deployment
- **Resource Right-Sizing**: Automatic resource allocation based on workload patterns
- **Spot Instance Support**: Add EC2 Spot instance support for cost optimization

#### 5. IAM Policy Refactoring

- **Externally Managed Policies**: Convert inline IAM policies to externally managed + attachments
- **Least Privilege Refinement**: Regular review and tightening of IAM permissions
- **Cross-Account Roles**: Support for cross-account deployments and centralized IAM

#### 6. Advanced Scaling

- **Predictive Scaling**: ML-based scaling predictions based on historical pipeline patterns
- **Multi-Metric Scaling**: KEDA scaling based on multiple metrics (queue depth, CPU, memory)
- **Custom Metrics**: Pipeline-specific metrics for more intelligent scaling decisions

### Developer Experience

#### 7. Enhanced Tooling

- **Terraform Cloud Integration**: Remote state management and collaborative workflows
- **GitOps Workflows**: ArgoCD or Flux for Kubernetes manifest management
- **Local Development**: Improved local testing with kind/minikube integration
- **Pipeline Templates**: Reusable Azure DevOps pipeline templates for common patterns

#### 8. Container Image Management

- **Multi-Arch Builds**: Automated ARM64/AMD64 builds with BuildKit
- **Image Optimization**: Distroless or minimal base images for security and performance
- **Registry Mirror**: Regional ECR mirrors for faster image pulls
- **Image Promotion**: Automated promotion pipeline from dev to staging to production

#### 9. Configuration Management

- **Helm Charts**: Package Kubernetes manifests as Helm charts for easier management
- **Environment Templating**: Support for dev/staging/production environment variations
- **Config Validation**: Automated validation of Terraform and Kubernetes configurations

### Operational Excellence

#### 10. Cost Optimization

- **Resource Tagging Strategy**: Comprehensive cost allocation and tracking
- **Automated Cleanup**: Scheduled cleanup of unused resources and images
- **Cost Monitoring**: Alerts and dashboards for infrastructure spend tracking
- **Reserved Instance Planning**: Automated recommendations for RI purchases

#### 11. Compliance and Governance

- **CIS Benchmarks**: Automated compliance checking against CIS Kubernetes benchmarks
- **SOC 2 Compliance**: Documentation and controls for compliance frameworks
- **Audit Logging**: Comprehensive audit trail for all cluster and infrastructure changes
- **Policy Enforcement**: Automated policy compliance checking and remediation

#### 12. Documentation and Training

- **Interactive Tutorials**: Step-by-step deployment walkthroughs
- **Architecture Decision Records**: Document key design decisions and rationale
- **Troubleshooting Playbooks**: Comprehensive operational runbooks
- **Video Tutorials**: Visual guides for complex setup and configuration tasks

### Integration Enhancements

#### 13. CI/CD Pipeline Improvements

- **Pipeline as Code**: Azure DevOps YAML pipelines stored in repository
- **Automated Testing**: Infrastructure testing with Terratest or similar
- **Security Scanning**: Integrated SAST/DAST scanning in deployment pipeline
- **Deployment Gates**: Automated quality gates and approval workflows

#### 14. Third-Party Integrations

- **Slack/Teams Notifications**: Real-time alerts and status updates
- **JIRA Integration**: Automatic ticket creation for deployment failures
- **PagerDuty Integration**: Escalation policies for critical incidents
- **External DNS**: Automatic DNS management for applications

### Performance and Scalability

#### 15. Advanced Networking

- **VPC CNI Optimization**: Tune networking for maximum pod density
- **Load Balancer Optimization**: Application Load Balancer integration for ingress
- **CDN Integration**: CloudFront integration for artifact and image caching

#### 16. Data Management

- **Persistent Storage**: EBS CSI driver integration for stateful workloads
- **Database Integration**: RDS proxy integration for database connections
- **Caching Strategy**: Redis/ElastiCache integration for build caching

These improvements should be prioritized based on organizational needs, with monitoring/observability and security hardening typically taking precedence for production deployments.

## Contributing

1. Follow the existing modular architecture
2. Test changes in non-production environments
3. Run security scans with `make checkov`
4. Update documentation for any new features
5. Use semantic versioning for releases
