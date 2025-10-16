# Example: Creating Multiple ECR Repositories

This example demonstrates how to use the new ECR module to create multiple repositories.

## Single Repository (Legacy - still supported)
```hcl
# Using the legacy approach (still works)
create_ecr_repository = true
ecr_repository_name   = "my-app"
```

## Multiple Repositories (New functionality)
```hcl
# Using the new ecr_repositories variable
ecr_repositories = {
  # Default repository (maintains backward compatibility)
  default = {
    repository_name         = "ado-agent-cluster-ado-agents"
    image_tag_mutability   = "MUTABLE"
    encryption_type        = "KMS"
    kms_key_arn           = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    scan_on_push          = true
    lifecycle_untagged_days = 7
    keep_tagged_count     = 10
  }
  
  # Additional application repository
  frontend = {
    repository_name         = "my-app-frontend"
    image_tag_mutability   = "IMMUTABLE"
    encryption_type        = "AES256"
    scan_on_push          = true
    lifecycle_untagged_days = 3
    keep_tagged_count     = 5
  }
  
  # Backend service repository
  backend = {
    repository_name         = "my-app-backend"
    image_tag_mutability   = "MUTABLE"
    encryption_type        = "AES256"
    scan_on_push          = true
    lifecycle_untagged_days = 14
    keep_tagged_count     = 20
  }
}
```

## Outputs Available

### Legacy Outputs (for backward compatibility)
- `ecr_repository_name` - Name of the first repository
- `ecr_repository_arn` - ARN of the first repository  
- `ecr_repository_url` - URL of the first repository
- `ecr_registry_id` - Registry ID of the first repository
- `ecr_bastion_policy_arn` - ARN of the bastion policy

### New Multi-Repository Outputs
- `ecr_repository_names` - Map of all repository names
- `ecr_repository_arns` - Map of all repository ARNs
- `ecr_repository_urls` - Map of all repository URLs
- `ecr_pull_policy_arn` - ARN of the pull policy (works for all repos)

## IAM Policy Benefits

The new modular approach creates IAM policies that automatically grant access to **all** ECR repositories managed by this module:

- **Pull Policy**: Grants pull access to all repositories for EKS workloads
- **Bastion Policy**: Grants push/pull access to all repositories for bastion hosts
- **Automatic Attachment**: Policies are automatically attached to the appropriate roles

This means when you add new repositories, the existing IAM policies automatically include them without needing manual updates.
