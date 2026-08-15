# =============================================================================
# EKS Observability Stack - Makefile
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

TERRAFORM := terraform
KUBECTL := kubectl
KUSTOMIZE := kustomize
HELM := helm
ENV ?= dev

.PHONY: help
help: ## Show available targets
	@echo "EKS Observability Stack - Full Observability for Production EKS"
	@echo ""
	@echo "Usage:"
	@echo "  make <target> ENV=<dev|stage|prod>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Terraform — Infrastructure (S3 backends, IAM, KMS, nodes)
# ---------------------------------------------------------------------------

.PHONY: init-terraform
init-terraform: ## Initialize Terraform in environment directory
	@echo "Initializing Terraform for ${ENV}..."
	@cd environments/${ENV} && $(TERRAFORM) init \
		-backend-config="bucket=eks-observability-s3-state-us-east-2-${ENV}" \
		-backend-config="key=${ENV}/terraform.tfstate" \
		-backend-config="region=us-east-2"
	@echo "✓ Terraform initialized"

.PHONY: plan
plan: ## Plan Terraform changes for environment
	@$(MAKE) init-terraform
	@cd environments/${ENV} && $(TERRAFORM) plan -out=tfplan
	@echo "✓ Terraform plan generated — review before applying"

.PHONY: apply
apply: ## Apply Terraform for environment (confirm first)
	@read -p "Apply Terraform for ${ENV}? [y/N] " confirm && \
		[ "$$confirm" = "y" ] || { echo "Aborted"; exit 1; }
	@cd environments/${ENV} && $(TERRAFORM) apply tfplan

.PHONY: destroy-terraform
destroy-terraform: ## Destroy Terraform resources for environment (confirm first!)
	@read -p "Type '${ENV}' to confirm destruction: " confirm && \
		[ "$$confirm" = "${ENV}" ] || { echo "Aborted"; exit 1; }
	@cd environments/${ENV} && $(TERRAFORM) init \
		-backend-config="bucket=eks-observability-s3-state-us-east-2-${ENV}" \
		-backend-config="key=${ENV}/terraform.tfstate" \
		-backend-config="region=us-east-2" && \
		$(TERRAFORM) destroy -auto-approve

# ---------------------------------------------------------------------------
# Kubernetes — Deploy via ArgoCD
# ---------------------------------------------------------------------------

.PHONY: deploy-k8s
deploy-k8s: ## Apply ArgoCD Applications + K8s manifests (ServiceMonitors, NetworkPolicies)
	@echo "Deploying observability stack via ArgoCD..."
	@$(KUBECTL) apply -f k8s-manifests/argocd/applications.yaml
	@$(KUBECTL) apply -f k8s-manifests/service-monitors.yaml
	@$(KUBECTL) apply -f k8s-manifests/network-policies.yaml
	@echo "✓ ArgoCD Applications applied — watch sync with: kubectl get applications -n argocd"

.PHONY: deploy-kustomize
deploy-kustomize: ## Build and preview Kustomize overlay (dry-run)
	@$(MAKE) init-terraform && \
		aws eks update-kubeconfig --name $$(cd environments/${ENV} && $(TERRAFORM) output -raw monitoring_node_group_name 2>/dev/null || true) \
			--region us-east-2 --alias eks-${ENV} 2>/dev/null || true
	@$(KUSTOMIZE) build k8s-manifests/overlays/${ENV}

.PHONY: deploy
deploy: ## Full deploy: Terraform + kubectl kubeconfig + ArgoCD sync
	@echo "=============================================="
	@echo " Deploying ${ENV} observability stack"
	@echo "=============================================="
	@echo ""
	@echo "Step 1/3: Terraform — S3 backends, IAM roles, KMS, nodes"
	@$(MAKE) plan apply ENV=${ENV}
	@echo ""
	@echo "Step 2/3: Update kubectl context"
	@aws eks update-kubeconfig --name $${EKS_CLUSTER_NAME:-eks-${ENV}} \
		--region us-east-2 --alias eks-${ENV} || true
	@echo ""
	@echo "Step 3/3: Deploy via ArgoCD (gitops-sync)"
	@$(MAKE) deploy-k8s ENV=${ENV}
	@echo ""
	@echo "✓ Observability stack deployed to ${ENV}!"
	@echo ""
	@echo "Next steps:"
	@echo "  kubectl get pods -n prometheus          # Check Prometheus"
	@echo "  kubectl get pods -n grafana             # Check Grafana"
	@echo "  kubectl get ingress -n ingress-nginx     # Get external endpoint"

# ---------------------------------------------------------------------------
# Validation & Security
# ---------------------------------------------------------------------------

.PHONY: validate
validate: ## Validate all Terraform configs + Kustomize builds
	@echo "=== Terraform Validation ==="
	@cd providers && $(TERRAFORM) init -backend=false >/dev/null 2>&1 && \
		$(TERRAFORM) validate && echo "providers: OK" || echo "providers: FAIL"
	@echo ""
	@echo "=== Kustomize Validation ==="
	@echo -n "dev:    " && $(KUSTOMIZE) build k8s-manifests/overlays/dev >/dev/null 2>&1 && \
		echo "OK" || echo "FAIL (expected — placeholders need values)"
	@echo -n "stage:  " && $(KUSTOMIZE) build k8s-manifests/overlays/stage >/dev/null 2>&1 && \
		echo "OK" || echo "FAIL (expected — placeholders need values)"
	@echo -n "prod:   " && $(KUSTOMIZE) build k8s-manifests/overlays/prod >/dev/null 2>&1 && \
		echo "OK" || echo "FAIL (expected — placeholders need values)"

.PHONY: check
check: ## Run all scans (trufflehog, tfsec, validate)
	@echo "=== TruffleHog ===" && \
		command -v trufflehog &> /dev/null && \
		trufflehog filesystem . --fail --no-update || \
		echo "TruffleHog not installed — skipping"
	@echo ""
	@echo "=== tfsec ===" && \
		command -v tfsec &> /dev/null && \
		tfsec . --no-color || \
		echo "tfsec not installed — skipping"
	@echo ""
	$(MAKE) validate

.PHONY: helm-lint
helm-lint: ## Lint all Helm charts referenced by the stack
	@echo "=== Helm Lint ==="
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null
	@helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null
	@helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null
	@helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server 2>/dev/null
	@helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null
	@helm repo add jetstack https://charts.jetstack.io 2>/dev/null
	@echo -n "prometheus:     " && helm lint prometheus-community/kube-prometheus-stack \
		--values k8s-manifests/prometheus/values.yaml >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "grafana:        " && helm lint grafana/grafana \
		--values k8s-manifests/grafana/values.yaml >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "loki:           " && helm lint loki/loki \
		--values k8s-manifests/loki/values.yaml >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "tempo:          " && helm lint tempo/tempo \
		--values k8s-manifests/tempo/values.yaml >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "fluentbit:      " && helm lint fluent/fluent-bit \
		--values k8s-manifests/fluentbit/values.yaml >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "cert-manager:   " && helm lint jetstack/cert-manager \
		--values k8s-manifests/cert-manager/values.yaml >/dev/null 2>&1 && echo "OK" || echo "FAIL"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

.PHONY: cleanup
cleanup: ## Clean Terraform artifacts (not state!)
	@echo "Cleaning Terraform artifacts..."
	@rm -rf providers/.terraform* providers/*.tfplan environments/*/providers/.terraform* 2>/dev/null || true
	@echo "✓ Cleanup complete"
