# ADO EKS Cluster Module

This module creates an Amazon EKS cluster specifically configured for Azure DevOps (ADO) agent workloads running on AWS Fargate.

## Features

- **EKS Cluster**: Fully managed Kubernetes cluster with configurable security and networking
- **Fargate Profiles**: Serverless compute for pods (application and system profiles)
- **KEDA Operator**: Auto-scaling based on Azure DevOps pipeline queues
- **External Secrets Operator**: Secure secret management from AWS Secrets Manager
- **VPC Endpoints**: Optional private connectivity to AWS services
- **ADO Agent Execution Roles**: IAM roles with specific permissions for different agent workloads

## ADO Agent Execution Roles

This module supports creating IAM roles for ADO agents with specific permissions tailored to different workloads:

### Default Roles

1. **dev-build**: For development and build workloads
   - ECR push/pull permissions for container image management
   - Scoped to specific repositories for security

2. **iac**: For Infrastructure as Code workloads
   - Administrative permissions to create/manage AWS resources
   - Full account access for Terraform/CloudFormation operations

### Configuration

```hcl
module "ado_eks_cluster" {
  source = "./modules/collections/ado-eks-cluster"
  
  # Enable ADO execution roles
  create_ado_execution_roles = true
  
  # Customize roles (optional - defaults shown below)
  ado_execution_roles = {
    dev-build = {
      service_account_name = "ado-agent-dev-build"
      permissions = [
        {
          effect = "Allow"
          actions = [
            "ecr:GetAuthorizationToken"
          ]
          resources = ["*"]
        },
        {
          effect = "Allow"
          actions = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:PutImage"
          ]
          resources = ["*"]
        }
      ]
    }
    iac = {
      service_account_name = "ado-iac-agent"
      permissions = [
        {
          effect = "Allow"
          actions = ["*"]
          resources = ["*"]
        }
      ]
    }
  }
}
```

### Adding Custom Roles

To add additional execution roles:

```hcl
ado_execution_roles = {
  # Existing roles...
  
  custom-role = {
    service_account_name = "ado-agent-custom"
    permissions = [
      {
        effect = "Allow"
        actions = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        resources = [
          "arn:aws:s3:::my-bucket/*"
        ]
        condition = {
          test     = "StringEquals"
          variable = "aws:RequestedRegion"
          values   = ["us-west-2"]
        }
      }
    ]
  }
}
```

### Referencing Existing IAM Roles

If you already manage the IAM role elsewhere, provide its ARN and skip permission statements:

```hcl
ado_execution_roles = {
  external = {
    service_account_name = "ado-agent-external"
    namespace            = "ado-agents"
    existing_role_arn    = "arn:aws:iam::123456789012:role/existing-ado-agent"
    permissions          = []
  }
}
```

The module will not create or update the role, but it will include the ARN in the outputs and service-account annotations.

### Attaching Additional Managed Policies

For roles managed by this module, you can attach extra IAM policies in addition to the inline statements:

```hcl
ado_execution_roles = {
  dev-build = {
    service_account_name = "ado-agent-dev-build"
    namespace            = "ado-agents"
    permissions = [
      {
        effect    = "Allow"
        actions   = ["ecr:GetAuthorizationToken"]
        resources = ["*"]
      }
    ]
    attach_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
    ]
  }
}
```

### Kubernetes Integration

The module outputs service account annotations that can be used in your Kubernetes ServiceAccount manifests:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ado-agent-dev-build
  namespace: ado-agents
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/CLUSTER-ado-agent-dev-build-role
```

## Outputs

- `ado_agent_execution_role_arns`: Map of role names to ARNs
- `ado_agent_execution_role_names`: Map of role names to role names
- `ado_agent_service_account_annotations`: Ready-to-use annotations for Kubernetes ServiceAccounts

## Security Considerations

- Roles use IAM Roles for Service Accounts (IRSA) for secure, temporary credential access
- Each role is scoped to specific service accounts and namespaces
- Permissions follow the principle of least privilege
- The `iac` role has administrative access - use with caution and proper access controls

## Best Practices

1. **Scope Permissions**: Customize permissions to match your specific use cases
2. **Use Conditions**: Add IAM policy conditions to further restrict access
3. **Regular Review**: Periodically review and audit role permissions
4. **Separate Environments**: Use different roles for dev/staging/prod environments
5. **Monitor Usage**: Enable CloudTrail logging to monitor role usage
