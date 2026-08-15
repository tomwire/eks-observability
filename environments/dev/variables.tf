# =============================================================================
# EKS Observability Stack - Dev Environment Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "eks_cluster_name" {
  description = "EKS cluster name from enterprise-terraform-aws (dev)"
  type        = string
}

variable "node_subnet_ids" {
  description = "Private subnet IDs from enterprise-terraform-aws (dev)"
  type        = list(string)
}

variable "eks_node_role_arn" {
  description = "Node IAM role ARN from enterprise-terraform-aws (dev)"
  type        = string
}

variable "eks_oidc_arn" {
  description = "OIDC provider ARN from enterprise-terraform-aws (dev)"
  type        = string
}

variable "eks_oidcissuer" {
  description = "OIDC issuer URL from enterprise-terraform-aws (dev)"
  type        = string
}

variable "common_tags" {
  description = "Common tags for dev environment"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "eks-observability"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
  }
}
