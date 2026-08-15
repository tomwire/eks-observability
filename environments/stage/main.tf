# =============================================================================
# EKS Observability Stack - Stage Environment
# =============================================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = merge(var.common_tags, {
    Environment = "stage"
    Project     = "eks-observability"
  })
}

module "observability_infra" {
  source = "../../providers"

  aws_region          = var.aws_region
  environment         = "stage"
  eks_cluster_name    = var.eks_cluster_name
  node_subnet_ids     = var.node_subnet_ids
  eks_node_role_arn   = var.eks_node_role_arn
  eks_oidc_arn        = var.eks_oidc_arn
  eks_oidcissuer      = var.eks_oidcissuer

  monitoring_node_instance_types = ["t3.large"]
  monitoring_node_count          = 2
  monitoring_node_min_count      = 1
  monitoring_node_max_count      = 5

  prometheus_retention_days = 30

  common_tags = local.common_tags
}

output "prometheus_bucket" { value = module.observability_infra.prometheus_bucket }
output "loki_bucket"       { value = module.observability_infra.loki_bucket }
output "tempo_bucket"      { value = module.observability_infra.tempo_bucket }
output "grafana_bucket"    { value = module.observability_infra.grafana_bucket }
output "monitoring_node_group_name" { value = module.observability_infra.monitoring_node_group_name }
