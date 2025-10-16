terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

provider "aws" {
  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.ado_eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.ado_eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.ado_eks_cluster.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.ado_eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.ado_eks_cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.ado_eks_cluster.cluster_name]
    }
  }
}
