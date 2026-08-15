# =============================================================================
# EKS Observability Stack - Stage Environment Variables
# =============================================================================

variable "aws_region"          { type = string; default = "us-east-2" }
variable "eks_cluster_name"    { type = string }
variable "node_subnet_ids"     { type = list(string) }
variable "eks_node_role_arn"   { type = string }
variable "eks_oidc_arn"        { type = string }
variable "eks_oidcissuer"      { type = string }

variable "common_tags" {
  type = map(string)
  default = {
    Environment = "stage"
    Project     = "eks-observability"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
  }
}
