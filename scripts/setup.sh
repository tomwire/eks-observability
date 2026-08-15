#!/usr/bin/env bash
# =============================================================================
# EKS Observability Stack - Environment Setup Script
#
# Verifies prerequisites, configures kubectl, and prepares for deployment.
# Must be run AFTER enterprise-terraform-aws has provisioned the cluster.
#
# Usage: ./scripts/setup.sh <environment> [eks_cluster_name]
#   environment: dev | stage | prod (required)
#   eks_cluster_name: optional — if omitted, defaults to "eks-{env}"
# =============================================================================

set -euo pipefail

ENV="${1:?Usage: $0 <dev|stage|prod> [cluster_name]}"
CLUSTER_NAME="${2:-eks-${ENV}}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------

check_cmd() {
  command -v "$1" &>/dev/null || error "$1 is required but not installed."
}

info "Checking prerequisites for ${ENV} environment..."
check_cmd terraform
check_cmd kubectl
check_cmd aws
check_cmd helm

# Verify AWS credentials
aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured."

# Verify EKS cluster exists
CLUSTER_EXISTS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region us-east-2 2>/dev/null | grep -c '"status": "ACTIVE"' || true)
if [ "$CLUSTER_EXISTS" != "1" ]; then
  error "EKS cluster '${CLUSTER_NAME}' not found or not active.\nProvision the cluster first with:\n  cd ../enterprise-terraform-aws && ./scripts/setup.sh ${ENV}"
fi

info "All prerequisites verified."

# ---------------------------------------------------------------------------
# Configure kubectl
# ---------------------------------------------------------------------------

info "Configuring kubectl for cluster '${CLUSTER_NAME}'..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region us-east-2 --alias "eks-${ENV}"
kubectl cluster-info | head -1

# ---------------------------------------------------------------------------
# Verify OIDC provider exists (needed for IRSA)
# ---------------------------------------------------------------------------

OIDC_PROVIDER=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || echo "")
if [ -z "$OIDC_PROVIDER" ]; then
  warn "OIDC provider not found for cluster '${CLUSTER_NAME}'."
  warn "IRSA will not work until OIDC is configured."
  warn "Run: eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve"
else
  info "OIDC provider found: ${OIDC_PROVIDER}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
info "Setup complete for ${ENV} environment."
echo ""
echo "Next steps:"
echo "  1. Run 'make init-terraform' to initialize Terraform backend"
echo "  2. Pass cluster outputs from enterprise-terraform-aws as variables:"
echo "     - eks_cluster_name=${CLUSTER_NAME}"
echo "     - node_subnet_ids=<private subnets>"
echo "     - eks_node_role_arn=<node role ARN>"
echo "     - eks_oidc_arn=<OIDC provider ARN>"
echo "     - eks_oidcissuer=<issuer URL>"
echo ""
echo "  3. Deploy: make deploy ENV=${ENV}"
