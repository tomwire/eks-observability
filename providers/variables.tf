# =============================================================================
# EKS Observability Stack - Terraform Variables
#
# These variables are typically passed from the enterprise-terraform-aws
# environment outputs. Each environment directory (dev/stage/prod) sets
# concrete values before running terraform init/plan/apply.
# =============================================================================

variable "aws_region" {
  description = "AWS region for all observability resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
}

# ---------------------------------------------------------------------------
# EKS Cluster Inputs — from enterprise-terraform-aws outputs
# ---------------------------------------------------------------------------

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (from enterprise-terraform-aws)"
  type        = string
}

variable "node_subnet_ids" {
  description = "Private subnet IDs for EKS node groups"
  type        = list(string)
}

variable "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role (from enterprise-terraform-aws)"
  type        = string
}

# ---------------------------------------------------------------------------
# OIDC Provider — for IRSA (IAM Roles for Service Accounts)
# ---------------------------------------------------------------------------

variable "eks_oidc_arn" {
  description = "ARN of the EKS cluster OIDC provider identity pool (from enterprise-terraform-aws)"
  type        = string
}

variable "eks_oidcissuer" {
  description = "The OIDC issuer URL for the EKS cluster, e.g. https://oidc.eks.us-east-2.amazonaws.com/id/ABC123"
  type        = string
}

# ---------------------------------------------------------------------------
# Monitoring Node Group Configuration
# ---------------------------------------------------------------------------

variable "monitoring_node_instance_types" {
  description = "EC2 instance types for the monitoring node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "monitoring_node_count" {
  description = "Desired number of monitoring nodes"
  type        = number
  default     = 1
}

variable "monitoring_node_min_count" {
  description = "Minimum number of monitoring nodes (autoscaling lower bound)"
  type        = number
  default     = 1
}

variable "monitoring_node_max_count" {
  description = "Maximum number of monitoring nodes (autoscaling upper bound)"
  type        = number
  default     = 5
}

# ---------------------------------------------------------------------------
# Retention & Sizing
# ---------------------------------------------------------------------------

variable "prometheus_retention_days" {
  description = "Number of days to retain Prometheus data before lifecycle expiration"
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Tagging — mirrors enterprise-terraform-aws convention
# ---------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources (mirrors enterprise-terraform-aws)"
  type        = map(string)
  default = {
    Project    = "eks-observability"
    ManagedBy  = "terraform"
    CostCenter = "engineering"
  }
}
