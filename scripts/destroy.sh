#!/usr/bin/env bash
# =============================================================================
# EKS Observability Stack - Environment Destroy Script
#
# Removes observability stack resources (S3 buckets, KMS keys, IAM roles,
# monitoring node group). Does NOT destroy the EKS cluster.
#
# Usage: ./scripts/destroy.sh <environment> [cluster_name]
# =============================================================================

set -euo pipefail

ENV="${1:?Usage: $0 <dev|stage|prod> [cluster_name]}"
CLUSTER_NAME="${2:-eks-${ENV}}"

warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
info() { echo -e "\033[0;32m[INFO]\033[0m $*"; }

# ---------------------------------------------------------------------------
# Confirm destruction
# ---------------------------------------------------------------------------

warn "This will destroy ALL observability stack resources for '${ENV}'."
warn "S3 buckets, KMS keys, IAM roles, and the monitoring node group will be deleted."
echo ""
read -p "Type '${ENV}' to confirm destruction: " confirm
[ "$confirm" = "${ENV}" ] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# Destroy k8s resources
# ---------------------------------------------------------------------------

info "Removing Kubernetes resources..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region us-east-2 --alias "eks-${ENV}" 2>/dev/null || true
kubectl delete -f k8s-manifests/argocd/applications.yaml 2>/dev/null || true
kubectl delete namespaces prometheus grafana loki tempo alertmanager ingress-nginx fluentbit 2>/dev/null || true

# ---------------------------------------------------------------------------
# Destroy Terraform resources
# ---------------------------------------------------------------------------

info "Destroying Terraform infrastructure..."
cd environments/${ENV}
terraform init \
  -backend-config="bucket=eks-observability-s3-state-us-east-2-${ENV}" \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="region=us-east-2" >/dev/null 2>&1
terraform destroy -auto-approve

echo ""
info "Destruction complete for ${ENV} environment."
echo "The EKS cluster '${CLUSTER_NAME}' remains intact."
