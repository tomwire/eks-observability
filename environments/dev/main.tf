# =============================================================================
# EKS Observability Stack - Dev Environment
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
    encrypt        = true
    # Configure via environment variables or CLI -override flags
    # bucket = "eks-observability-s3-state-us-east-2-dev"
    # key    = "dev/terraform.tfstate"
    # region = "us-east-2"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = merge(var.common_tags, {
    Environment = "dev"
    Project     = "eks-observability"
  })
}

# ---------------------------------------------------------------------------
# Provider module (shared infrastructure)
# ---------------------------------------------------------------------------

module "observability_infra" {
  source = "../../providers"

  # AWS
  aws_region = var.aws_region
  environment = "dev"

  # EKS cluster inputs — replace with actual values or pass via CLI -var-file
  eks_cluster_name    = var.eks_cluster_name
  node_subnet_ids     = var.node_subnet_ids
  eks_node_role_arn   = var.eks_node_role_arn
  eks_oidc_arn        = var.eks_oidc_arn
  eks_oidcissuer      = var.eks_oidcissuer

  # Monitoring nodes
  monitoring_node_instance_types = ["t3.large"]
  monitoring_node_count          = 1
  monitoring_node_min_count      = 1
  monitoring_node_max_count      = 3

  # Retention
  prometheus_retention_days = 7

  # Tagging
  common_tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Outputs — surfaced for CI/CD and documentation
# ---------------------------------------------------------------------------

output "prometheus_bucket" {
  value = module.observability_infra.prometheus_bucket
}

output "loki_bucket" {
  value = module.observability_infra.loki_bucket
}

output "tempo_bucket" {
  value = module.observability_infra.tempo_bucket
}

output "grafana_bucket" {
  value = module.observability_infra.grafana_bucket
}

output "monitoring_node_group_name" {
  value = module.observability_infra.monitoring_node_group_name
}
