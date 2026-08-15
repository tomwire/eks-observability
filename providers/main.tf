# =============================================================================
# EKS Observability Stack - Terraform Infrastructure
#
# Manages the underlying AWS infrastructure for the observability stack:
#   - S3 buckets for Prometheus TSDB, Loki logs, Tempo traces, Grafana data
#   - KMS keys for encryption at rest (per-backend)
#   - IAM roles + policies for IRSA (Prometheus, Loki, Tempo → S3)
#   - EKS node group dedicated to observability workloads
#   - AWS Load Balancer Controller IAM role for ingress-nginx NLB
#
# Designed as a companion to enterprise-terraform-aws which provisions the EKS cluster.
# This module consumes cluster outputs (name, subnets, node role ARN) as variables.
# =============================================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.common_tags, {
      Environment = var.environment
      Project     = "eks-observability"
      ManagedBy   = "terraform"
    })
  }
}

# ---------------------------------------------------------------------------
# Random suffix for unique resource names
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# KMS Keys — One key per observability backend
# =============================================================================

resource "aws_kms_key" "prometheus" {
  description             = "KMS key for Prometheus TSDB S3 bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Component = "kms"
    Purpose   = "Prometheus TSDB encryption"
  }
}

resource "aws_kms_alias" "prometheus" {
  name          = "alias/eks-observability-prometheus-${var.environment}"
  target_key_id = aws_kms_key.prometheus.key_id
}

resource "aws_kms_key" "loki" {
  description             = "KMS key for Loki log S3 bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Component = "kms"
    Purpose   = "Loki logs encryption"
  }
}

resource "aws_kms_alias" "loki" {
  name          = "alias/eks-observability-loki-${var.environment}"
  target_key_id = aws_kms_key.loki.key_id
}

resource "aws_kms_key" "tempo" {
  description             = "KMS key for Tempo trace S3 bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Component = "kms"
    Purpose   = "Tempo traces encryption"
  }
}

resource "aws_kms_alias" "tempo" {
  name          = "alias/eks-observability-tempo-${var.environment}"
  target_key_id = aws_kms_key.tempo.key_id
}

resource "aws_kms_key" "grafana" {
  description             = "KMS key for Grafana data S3 bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Component = "kms"
    Purpose   = "Grafana data encryption"
  }
}

resource "aws_kms_alias" "grafana" {
  name          = "alias/eks-observability-grafana-${var.environment}"
  target_key_id = aws_kms_key.grafana.key_id
}

# =============================================================================
# S3 Buckets — Prometheus TSDB, Loki logs, Tempo traces, Grafana data
# =============================================================================

resource "aws_s3_bucket" "prometheus" {
  bucket = "eks-observability-prometheus-${var.environment}-${random_id.suffix.hex}"

  tags = {
    Component = "prometheus"
    Purpose   = "Time-series database persistence (remote-write)"
  }
}

resource "aws_s3_bucket_versioning" "prometheus" {
  bucket = aws_s3_bucket.prometheus.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prometheus" {
  bucket = aws_s3_bucket.prometheus.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.prometheus.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "prometheus" {
  bucket                  = aws_s3_bucket.prometheus.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "prometheus" {
  bucket = aws_s3_bucket.prometheus.id
  rule {
    id     = "expire-old-data"
    status = "Enabled"
    filter {}
    expiration {
      days = var.prometheus_retention_days
    }
  }
}

resource "aws_s3_bucket_logging" "prometheus" {
  bucket        = aws_s3_bucket.prometheus.id
  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "s3-access-logs/prometheus/"
}

# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "loki" {
  bucket = "eks-observability-loki-${var.environment}-${random_id.suffix.hex}"

  tags = {
    Component = "loki"
    Purpose   = "Log object storage backend"
  }
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.loki.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "loki" {
  bucket        = aws_s3_bucket.loki.id
  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "s3-access-logs/loki/"
}

# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tempo" {
  bucket = "eks-observability-tempo-${var.environment}-${random_id.suffix.hex}"

  tags = {
    Component = "tempo"
    Purpose   = "Trace object storage backend"
  }
}

resource "aws_s3_bucket_versioning" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tempo.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket                  = aws_s3_bucket.tempo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "tempo" {
  bucket        = aws_s3_bucket.tempo.id
  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "s3-access-logs/tempo/"
}

# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "grafana" {
  bucket = "eks-observability-grafana-${var.environment}-${random_id.suffix.hex}"

  tags = {
    Component = "grafana"
    Purpose   = "Dashboard exports, snapshot storage, provisioning"
  }
}

resource "aws_s3_bucket_versioning" "grafana" {
  bucket = aws_s3_bucket.grafana.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "grafana" {
  bucket = aws_s3_bucket.grafana.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.grafana.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "grafana" {
  bucket                  = aws_s3_bucket.grafana.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "grafana" {
  bucket        = aws_s3_bucket.grafana.id
  target_bucket = aws_s3_bucket.logging[0].id
  target_prefix = "s3-access-logs/grafana/"
}

# ---------------------------------------------------------------------------
# Central S3 logging bucket for all access logs
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logging" {
  count  = var.environment != "dev" ? 1 : 0
  bucket = "eks-observability-logs-${var.environment}-${random_id.suffix.hex}"

  tags = {
    Component = "logging"
    Purpose   = "Central S3 access log storage"
  }
}

# =============================================================================
# IAM Roles + Policies — IRSA for observability components → S3
# =============================================================================

# Prometheus: full read/write/list on its S3 bucket
resource "aws_iam_role" "prometheus_s3" {
  name = "eks-observability-prometheus-s3-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_arn
        }
        Condition = {
          StringEquals = {
            "${var.eks_oidcissuer}:sub" = "system:serviceaccount:prometheus:prometheus-prometheus"
          }
        }
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Prometheus S3 access via IRSA"
  }
}

resource "aws_iam_policy" "prometheus_s3" {
  name        = "eks-observability-prometheus-s3-${var.environment}"
  description = "Allow Prometheus to read/write TSDB data in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:PutObjectVersion",
        ]
        Resource = [
          aws_s3_bucket.prometheus.arn,
          "${aws_s3_bucket.prometheus.arn}/*",
        ]
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Prometheus S3 access policy"
  }
}

resource "aws_iam_role_policy_attachment" "prometheus_s3" {
  role       = aws_iam_role.prometheus_s3.name
  policy_arn = aws_iam_policy.prometheus_s3.arn
}

# Loki: full read/write/list on its S3 bucket
resource "aws_iam_role" "loki_s3" {
  name = "eks-observability-loki-s3-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_arn
        }
        Condition = {
          StringEquals = {
            "${var.eks_oidcissuer}:sub" = "system:serviceaccount:loki:loki"
          }
        }
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Loki S3 access via IRSA"
  }
}

resource "aws_iam_policy" "loki_s3" {
  name        = "eks-observability-loki-s3-${var.environment}"
  description = "Allow Loki to read/write log objects in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:PutObjectVersion",
        ]
        Resource = [
          aws_s3_bucket.loki.arn,
          "${aws_s3_bucket.loki.arn}/*",
        ]
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Loki S3 access policy"
  }
}

resource "aws_iam_role_policy_attachment" "loki_s3" {
  role       = aws_iam_role.loki_s3.name
  policy_arn = aws_iam_policy.loki_s3.arn
}

# Tempo: full read/write/list on its S3 bucket
resource "aws_iam_role" "tempo_s3" {
  name = "eks-observability-tempo-s3-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_arn
        }
        Condition = {
          StringEquals = {
            "${var.eks_oidcissuer}:sub" = "system:serviceaccount:tempo:tempo"
          }
        }
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Tempo S3 access via IRSA"
  }
}

resource "aws_iam_policy" "tempo_s3" {
  name        = "eks-observability-tempo-s3-${var.environment}"
  description = "Allow Tempo to read/write trace objects in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:PutObjectVersion",
        ]
        Resource = [
          aws_s3_bucket.tempo.arn,
          "${aws_s3_bucket.tempo.arn}/*",
        ]
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Tempo S3 access policy"
  }
}

resource "aws_iam_role_policy_attachment" "tempo_s3" {
  role       = aws_iam_role.tempo_s3.name
  policy_arn = aws_iam_policy.tempo_s3.arn
}

# Grafana: read/write on its S3 bucket for snapshots and exports
resource "aws_iam_role" "grafana_s3" {
  name = "eks-observability-grafana-s3-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_arn
        }
        Condition = {
          StringEquals = {
            "${var.eks_oidcissuer}:sub" = "system:serviceaccount:grafana:grafana"
          }
        }
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Grafana S3 access via IRSA"
  }
}

resource "aws_iam_policy" "grafana_s3" {
  name        = "eks-observability-grafana-s3-${var.environment}"
  description = "Allow Grafana to read/write data in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          aws_s3_bucket.grafana.arn,
          "${aws_s3_bucket.grafana.arn}/*",
        ]
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "Grafana S3 access policy"
  }
}

resource "aws_iam_role_policy_attachment" "grafana_s3" {
  role       = aws_iam_role.grafana_s3.name
  policy_arn = aws_iam_policy.grafana_s3.arn
}

# =============================================================================
# AWS Load Balancer Controller — IAM role for ingress-nginx NLB provisioning
# =============================================================================

resource "aws_iam_role" "alb_controller" {
  name = "eks-observability-alb-controller-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_arn
        }
        Condition = {
          StringEquals = {
            "${var.eks_oidcissuer}:sub" = "system:serviceaccount:ingress-nginx:aws-load-balancer-controller"
          }
        }
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "AWS Load Balancer Controller for ingress-nginx NLB"
  }
}

resource "aws_iam_policy" "alb_controller" {
  name        = "eks-observability-alb-controller-${var.environment}"
  description = "Allow Load Balancer Controller to provision NLBs and manage security groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "eks:DescribeCluster",
          "elasticloadbalancing:*",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Component = "iam"
    Purpose   = "ALB Controller policy"
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# =============================================================================
# EKS Node Group — Dedicated monitoring nodes
# =============================================================================

resource "aws_eks_node_group" "monitoring" {
  cluster_name    = var.eks_cluster_name
  node_group_name = "monitoring-${var.environment}"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = var.monitoring_node_instance_types

  scaling_config {
    desired_size = var.monitoring_node_count
    max_size     = var.monitoring_node_max_count
    min_size     = var.monitoring_node_min_count
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "node.kubernetes.io/role"      = "monitoring"
    "prometheus.io/scrape"         = "true"
    "eks-observability/node-group" = "true"
  }

  taint {
    key    = "node.kubernetes.io/role"
    value  = "monitoring"
    effect = "PREFER_NO_SCHEDULE"
  }

  tags = {
    Component = "monitoring"
    Purpose   = "Observability stack workloads node group"
  }

  depends_on = [
    aws_iam_role.prometheus_s3,
    aws_iam_role.loki_s3,
    aws_iam_role.tempo_s3,
    aws_iam_role.grafana_s3,
    aws_iam_role.alb_controller,
  ]
}

# =============================================================================
# Outputs
# =============================================================================

output "prometheus_bucket" {
  description = "Prometheus S3 bucket for TSDB remote-write persistence"
  value       = aws_s3_bucket.prometheus.bucket
}

output "loki_bucket" {
  description = "Loki S3 bucket for log object storage"
  value       = aws_s3_bucket.loki.bucket
}

output "tempo_bucket" {
  description = "Tempo S3 bucket for trace object storage"
  value       = aws_s3_bucket.tempo.bucket
}

output "grafana_bucket" {
  description = "Grafana S3 bucket for dashboard exports and snapshots"
  value       = aws_s3_bucket.grafana.bucket
}

output "prometheus_kms_key_arn" {
  description = "KMS key ARN for Prometheus TSDB encryption"
  value       = aws_kms_key.prometheus.arn
}

output "loki_kms_key_arn" {
  description = "KMS key ARN for Loki log encryption"
  value       = aws_kms_key.loki.arn
}

output "tempo_kms_key_arn" {
  description = "KMS key ARN for Tempo trace encryption"
  value       = aws_kms_key.tempo.arn
}

output "grafana_kms_key_arn" {
  description = "KMS key ARN for Grafana data encryption"
  value       = aws_kms_key.grafana.arn
}

output "monitoring_node_group_name" {
  description = "EKS node group name for monitoring workloads"
  value       = aws_eks_node_group.monitoring.node_group_name
}

output "prometheus_s3_role_arn" {
  description = "IAM role ARN for Prometheus S3 access (IRSA)"
  value       = aws_iam_role.prometheus_s3.arn
  sensitive   = true
}

output "loki_s3_role_arn" {
  description = "IAM role ARN for Loki S3 access (IRSA)"
  value       = aws_iam_role.loki_s3.arn
  sensitive   = true
}

output "tempo_s3_role_arn" {
  description = "IAM role ARN for Tempo S3 access (IRSA)"
  value       = aws_iam_role.tempo_s3.arn
  sensitive   = true
}

output "grafana_s3_role_arn" {
  description = "IAM role ARN for Grafana S3 access (IRSA)"
  value       = aws_iam_role.grafana_s3.arn
  sensitive   = true
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
  sensitive   = true
}
