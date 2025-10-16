# # Use depends_on to ensure proper ordering
# data "aws_eks_cluster" "cluster" {
#   name       = module.ado_eks_cluster.cluster_name
#   depends_on = [module.ado_eks_cluster]
# }

# data "aws_eks_cluster_auth" "cluster" {
#   name       = module.ado_eks_cluster.cluster_name
#   depends_on = [module.ado_eks_cluster]
# }

# Read existing aws-auth configmap (if it exists)
# Use depends_on and ignore_errors to handle bootstrap scenario
data "kubernetes_config_map" "aws_auth" {
  count = var.enable_kube_auth_management ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  depends_on = [module.ado_eks_cluster]
}

locals {
  # Only process aws-auth when enabled and ConfigMap exists
  existing_maproles = var.enable_kube_auth_management && length(data.kubernetes_config_map.aws_auth) > 0 ? try(
    yamldecode(data.kubernetes_config_map.aws_auth[0].data["mapRoles"]),
    []
  ) : []

  # Extract role ARNs already present to avoid duplicates
  existing_maproles_rolearns = [for r in local.existing_maproles : try(r.rolearn, "")]

  bastion_entry = {
    rolearn  = var.bastion_role_arn
    username = "bastion-admin"
    groups   = ["system:masters"]
  }

  # Determine merged roles based on current state - ensure consistent ordering
  merged_maproles = var.enable_kube_auth_management ? (
    # If managing auth, merge with existing roles but ensure consistent order
    contains(local.existing_maproles_rolearns, var.bastion_role_arn) ?
    # Sort existing roles to ensure consistent ordering
    sort([for role in local.existing_maproles : jsonencode(role)]) :
    # Add bastion role and sort for consistency  
    sort([for role in concat(local.existing_maproles, [local.bastion_entry]) : jsonencode(role)])
    ) : (
    # If not managing auth yet, just add the bastion role for initial setup
    [jsonencode(local.bastion_entry)]
  )

  # Decode back to objects for YAML encoding
  final_maproles = [for role_json in local.merged_maproles : jsondecode(role_json)]
}

resource "kubernetes_config_map_v1_data" "aws_auth_patch" {
  count = var.enable_kube_auth_management ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.final_maproles)
  }

  depends_on = [module.ado_eks_cluster]

  force = true
}