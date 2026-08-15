# EKS Observability Stack

A production-grade, full-stack observability platform for Amazon EKS — Prometheus, Grafana, Loki, Tempo, and Alertmanager — deployed via ArgoCD GitOps with Kustomize overlays. Designed to integrate seamlessly with the [enterprise-terraform-aws](https://github.com/twire/enterprise-terraform-aws) repo which provisions the underlying EKS cluster.

> **Purpose:** Demonstrates enterprise-grade observability architecture: the complete PLT (Prometheus-Loki-Tempo) stack, GitOps deployment, multi-environment strategy, and production security patterns — all runnable in a single AWS account.

[![Terraform](https://img.shields.io/badge/Terraform-1.10+-orange.svg)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📋 Table of Contents

- [Architecture](#-architecture)
- [Components](#-components)
- [Integration with enterprise-terraform-aws](#-integration-with-enterprise-terraform-aws)
- [Environments](#-environments)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [CI Pipeline](#-ci-pipeline)
- [Key Patterns](#-key-patterns)
- [Cost Estimates](#-cost-estimates)
- [Security](#-security)
- [Destroy](#-destroy)
- [Interview Talking Points](#-interview-talking-points)

---

## 🏗️ Architecture

```
                         ┌──────────────────────────────────────────────────────┐
                         │              Amazon EKS Cluster                       │
                         │                                                       │
                         │  ┌─────────┐    ┌──────────┐    ┌──────────────┐      │
                         │  │ Prometheus│    │ Alert-   │    │    Grafana     │      │
                         │  │ (TSDB +  │◄──►│ manager  │◄──►│  Dashboards   │      │
                         │  │ Operator) │    │          │    │  & Datasources│      │
                         │  └────┬─────┘    └──────────┘    └──────┬───────┘      │
                         │       │                                │                │
                         │  ┌────▼─────┐               ┌──────────▼───────┐        │
                         │  │   Loki   │               │    Ingress-NGINX │        │
                         │  │ (Logs)   │               │  + cert-manager   │        │
                         │  └────┬─────┘               │   (TLS/HTTPS)     │        │
                         │       │                      └──────────────────┘        │
                         │  ┌────▼─────┐                                            │
                         │  │  Tempo   │                                            │
                         │  │(Traces)  │                                            │
                         │  └────┬─────┘                                            │
                         │       │                                                   │
                         │  ┌────▼───────────────────────────────────────────┐       │
                         │  │          FluentBit DaemonSet                    │       │
                         │  │     (EKS cluster log collection)               │       │
                         │  └────────────────────────────────────────────────┘       │
                         └──────────────────────────────────────────────────────┘
                                    ▲           ▲
                                    │           │ S3 Remote Storage
                        IRSA        │           │
                         │          │           │
                    ┌────▼──────────▼───────────▼──────────────┐
                    │             Amazon S3                     │
                    │  ┌──────────┐ ┌────────┐ ┌──────────┐    │
                    │  │Prometheus│ │ Loki   │ │  Tempo   │    │
                    │  │   TSDB   │ │  Logs  │ │  Traces  │    │
                    │  └──────────┘ └────────┘ └──────────┘    │
                    └───────────────────────────────────────────┘
```

### Data Flow

1. **Metrics:** kube-prometheus-stack scrapes all Kubernetes workloads via ServiceMonitors; Prometheus Operator manages alert rules and the Alertmanager integration
2. **Logs:** FluentBit DaemonSet runs on every node, collecting container logs and forwarding them to Loki through its gateway
3. **Traces:** Applications emit OpenTelemetry (OTLP) traces that Tempo ingests; metrics generator correlates traces with Prometheus metrics
4. **Visualization:** Grafana connects to all three backends (Prometheus/Loki/Tempo) and provides unified dashboards and alerting UI

---

## 🧩 Components

| Component | Helm Chart | Purpose | Namespace |
|-----------|-----------|---------|-----------|
| **Prometheus** | `kube-prometheus-stack` (61.x) | Metrics collection, storage, Alertmanager integration | `prometheus` |
| **Grafana** | `grafana` (8.6.x) | Dashboards, datasources, alerting UI, provisioning | `grafana` |
| **Loki** | `loki` (6.26.x) | Log aggregation with S3 object storage backend | `loki` |
| **Tempo** | `tempo` (1.8.x) | Distributed tracing with OTLP/Jaeger/Zipkin receivers | `tempo` |
| **Alertmanager** | Embedded in Prometheus chart | Alert routing, inhibition, deduplication | `prometheus` |
| **FluentBit** | `fluent-bit` (0.31.x) | Kubernetes DaemonSet — container log collection → Loki | `fluentbit` |
| **cert-manager** | `cert-manager` (1.15.x) | Automated TLS certificates via Let's Encrypt / ACM | `cert-manager` |
| **Ingress-NGINX** | `ingress-nginx` (4.11.x) | External access via NLB with cert-manager TLS termination | `ingress-nginx` |
| **Metrics Server** | `metrics-server` (3.12.x) | HPA, `kubectl top`, cluster autoscaler integration | `kube-system` |
| **ArgoCD** | App-of-Apps pattern | GitOps deployment and self-healing sync for all above | `argocd` |

### Storage Backend (S3)

All three backends (Prometheus TSDB, Loki logs, Tempo traces) use Amazon S3 as persistent object storage — eliminating the need for local EBS volumes on observability nodes:

| Backend | Bucket Prefix | Retention |
|---------|--------------|-----------|
| Prometheus | `eks-observability-prometheus-{env}` | 30 days (configurable) |
| Loki | `eks-observability-loki-{env}` | 72 hours |
| Tempo | `eks-observability-tempo-{env}` | Configurable compaction window |

All buckets have: versioning, server-side KMS encryption, public access blocked, lifecycle rules, and access logging.

---

## 🔗 Integration with enterprise-terraform-aws

This repo is a **companion** to [enterprise-terraform-aws](https://github.com/twire/enterprise-terraform-aws):

```
enterprise-terraform-aws          eks-observability
┌─────────────────────┐          ┌──────────────────────────┐
│ VPC + Subnets       │          │ S3 buckets (storage)     │
│ EKS Cluster         │─────────►│ Monitoring node group    │
│ RDS / Database      │  cluster │ IAM roles + IRSA         │
│ IRSA / OIDC         │  name,   │ KMS keys                 │
│ Networking          │  subnets│ Helm values               │
└─────────────────────┘  node    │ Kustomize overlays        │
              ▲            role   │ ArgoCD Applications       │
              │            ARN   │                          │
              └── Terraform outputs passed as variables ─────┘
```

The observability stack **consumes** the cluster infrastructure from `enterprise-terraform-aws` via:
- `eks_cluster_name` — EKS cluster name from the infra repo
- `node_subnet_ids` — Private subnets for node placement
- `eks_node_role_arn` — IAM role ARN for S3 access delegation

This separation keeps each repo focused and independently deployable.

---

## 🌍 Environments

| Environment | Monitoring Nodes | Prometheus Storage | Cost Focus |
|-------------|-----------------|-------------------|------------|
| **dev** | t3.large × 1 | 50GB gp3 | Minimal — development & testing |
| **stage** | t3.large × 2 | 100GB gp3 | Production-like workload simulation |
| **prod** | t3.xlarge × 3 | 500GB gp3 | Full production observability |

Each environment gets:
- **Dedicated S3 state bucket** with versioning & KMS encryption
- **Separate Kubernetes namespaces** (complete isolation)
- **Consistent tagging strategy** (environment, project, managedBy, costCenter)
- **Independent lifecycle** (apply/destroy per environment)

---

## 📁 Project Structure

```
eks-observability/
├── README.md                      # This file
├── Makefile                       # Deploy targets: make dev/stage/prod/destroy-*
├── LICENSE                        # MIT — Thomas Wire
│
├── .github/workflows/
│   └── ci.yml                     # GitHub Actions CI (fmt, validate, tfsec, trufflehog)
│
├── providers/                     # Terraform: S3 backends, IAM roles, KMS, nodes
│   ├── main.tf                    # Resource definitions
│   ├── variables.tf               # Input variables (consumes enterprise-terraform-aws outputs)
│   └── versions.tf                # Version constraints + S3 backend
│
├── environments/                  # Environment-specific Terraform entry points
│   ├── dev/                       # Dev environment setup
│   │   ├── main.tf
│   │   └── variables.tf
│   ├── stage/                     # Stage environment setup
│   │   ├── main.tf
│   │   └── variables.tf
│   └── prod/                      # Production environment setup
│       ├── main.tf
│       └── variables.tf
│
├── k8s-manifests/                 # Kubernetes + Helm configuration
│   ├── base/                      # Kustomize base (namespaces, storage config)
│   │   ├── namespaces.yaml
│   │   ├── storage-config-patch.yaml
│   │   └── kustomization.yaml
│   ├── overlays/                  # Per-environment patches
│   │   ├── dev/                   # Dev: minimal resources, 7d retention
│   │   ├── stage/                 # Stage: production-like sizing
│   │   └── prod/                  # Prod: full capacity, 90d retention
│   │
│   ├── prometheus/values.yaml     # Prometheus Operator + kube-prometheus-stack
│   ├── grafana/values.yaml        # Grafana dashboards + datasources
│   ├── loki/values.yaml           # Loki with S3 storage backend (schema v13)
│   ├── tempo/values.yaml          # Tempo with OTLP/Jaeger/Zipkin receivers
│   ├── alertmanager/values.yaml   # Alert routing and inhibition rules
│   ├── ingress/values.yaml        # Ingress-NGINX + NLB annotations
│   ├── metrics/values.yaml        # Metrics Server for HPA
│   ├── fluentbit/values.yaml      # FluentBit DaemonSet → Loki
│   ├── cert-manager/values.yaml   # cert-manager + ClusterIssuer (Let's Encrypt)
│   │
│   ├── service-monitors.yaml      # Prometheus ServiceMonitors for workload discovery
│   ├── network-policies.yaml      # K8s NetworkPolicies for component isolation
│   ├── alerting-rules.yaml        # PrometheusRule CRDs (infra, app, platform alerts)
│   │
│   └── argocd/                    # ArgoCD Application resources
│       └── applications.yaml      # GitOps sync for all components (8 charts)
```

---

## 📦 Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads.html) >= 1.10
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for EKS interaction
- [Helm](https://helm.sh/) >= 3.14 for chart management
- An AWS account with appropriate permissions (see below)

### Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*", "eks:*", "s3:*", "iam:*",
        "kms:*", "logs:*", "cloudwatch:*",
        "ssm:*", "elasticloadbalancing:*",
        "sts:AssumeRole", "acm:*", "route53:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Recommended Tooling

| Tool | Purpose |
|------|---------|
| `terraform` | Infrastructure provisioning |
| `kubectl` | Kubernetes cluster interaction |
| `helm` | Chart management (install, lint, upgrade) |
| `kustomize` | K8s manifest overlays |
| `tfsec` | Terraform security scanning |
| `trufflehog` | Secret scanning in git history |

---

## 🚀 Quick Start

### 1. Ensure the EKS cluster exists

The `enterprise-terraform-aws` repo provisions the underlying cluster. Follow its setup instructions first, then pass the outputs to this project:

```bash
cd ../enterprise-terraform-aws
./scripts/setup.sh dev
# After apply: note the cluster name, subnet IDs, and node role ARN from outputs
```

### 2. Deploy the observability stack

```bash
# Deploy to dev environment
make dev

# This runs: Terraform → kubectl kubeconfig update → ArgoCD sync
```

The Makefile handles the full lifecycle:
1. **Terraform** — Creates S3 buckets, KMS keys, IAM roles, monitoring node group
2. **kubeconfig** — Updates `kubectl` context for the EKS cluster
3. **ArgoCD** — Applies Application manifests that self-sync from Helm repos

### 3. Access the dashboards

After deployment, get the Ingress-NGINX external IP and access Grafana:

```bash
# Get the NLB address
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access via browser (cert-manager provisions TLS automatically)
# https://grafana.<domain>
# https://prometheus.<domain>
# https://loki.<domain>
```

---

## 🔄 CI Pipeline

Automated quality gates on every push/PR (GitHub Actions):

| Stage | Tool | What it checks |
|-------|------|----------------|
| **Format** | `terraform fmt -check` | Consistent code style |
| **Validate** | `terraform validate` | Syntax + provider compatibility |
| **Secrets** | TruffleHog `--only-verified` | No AWS keys, passwords, tokens committed |
| **Security** | tfsec | Insecure infrastructure configurations |
| **Kustomize** | `kustomize build` | All overlays produce valid manifests |
| **Helm Lint** | `helm lint` | Chart chart.yaml/values.yaml consistency |

To run locally:
```bash
make check           # All scans
make validate        # Terraform + Kustomize validation
```

---

## 🔑 Key Patterns

### 1. S3 as Universal Storage Backend

Instead of local EBS volumes for Prometheus TSDB, Loki logs, and Tempo traces — all three backends store data in S3:

- **Prometheus:** Remote write to S3 via Thanos sidecar pattern (future enhancement)
- **Loki:** Native S3 storage with schema v13 (TSDB index + objects in S3)
- **Tempo:** Direct S3 object store for trace blocks with compaction

This eliminates node disk pressure, simplifies backups, and enables cross-cluster query patterns.

### 2. IRSA for Service Account IAM

Observability components access S3 buckets without static credentials:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::...:role/eks-observability-prometheus-s3
```

The Terraform module creates IAM roles and policies, then the `eks.amazonaws.com/role-arn` annotation binds them to pod service accounts.

### 3. Kustomize + ArgoCD GitOps

Environment-specific customizations (replica counts, resource limits, ingress domains) live in Kustomize overlays. ArgoCD Applications watch Helm repos and self-heal drift automatically:

```
k8s-manifests/overlays/dev   → ArgoCD Application → dev namespace
k8s-manifests/overlays/prod  → ArgoCD Application → prod namespace
```

### 4. Alert Routing with Inhibition

Alertmanager routes critical alerts to dedicated receivers while grouping related warnings. Inhibition rules suppress warning alerts when the underlying cause is already a critical alert (e.g., node down → suppress all pod restart warnings on that node).

### 5. Unified Data Model (PLT Stack)

Prometheus (metrics), Loki (logs), and Tempo (traces) share common Kubernetes metadata labels (`app`, `namespace`, `pod`). This enables correlation:
- Click a trace span in Grafana → see related logs filtered by same pod label
- Click a metric anomaly → jump to logs from the affected namespace

---

## 💰 Cost Estimates (per environment)

| Resource | dev | stage | prod |
|----------|-----|-------|------|
| EKS Cluster control plane | $0.10/hr | $0.10/hr | $0.10/hr |
| Monitoring Nodes | ~$0.09/hr | ~$0.17/hr | ~$0.51/hr |
| S3 Storage (all backends) | ~$0.50/mo | ~$2.00/mo | ~$10.00/mo |
| NLB (Ingress-NGINX) | $0.025/hr | $0.025/hr | $0.025/hr |
| KMS Keys | <$0.01/hr | <$0.01/hr | <$0.01/hr |
| **~Total/hr** | **~$0.14** | **~$0.30** | **~$0.64** |
| **~Total/month** | **~$100** | **~$220** | **~$460** |

> 💡 **Tip:** Start with `dev` first. The EKS control plane ($0.10/hr) is the biggest fixed cost — destroy it when not in active use.

---

## 🔒 Security Highlights

| Feature | Implementation |
|---------|---------------|
| **Encryption at rest** | KMS-encrypted S3 buckets for all backends |
| **No public S3 access** | `block_public_acls`, `block_public_policy`, `restrict_public_buckets` |
| **IRSA for pod access** | No AWS credentials in env vars or secrets |
| **S3 bucket versioning** | Point-in-time recovery for all observability data |
| **Lifecycle policies** | Automatic data expiration (Prometheus 30d, Loki 72h) |
| **Network isolation** | Observability nodes in private subnets only |
| **Ingress TLS** | cert-manager provisions certificates via ACM/Let's Encrypt |
| **Container security context** | Non-root user (uid 472) for Grafana pods |

---

## 🧹 Destroy

```bash
# Clean up observability stack only (does NOT destroy the EKS cluster)
make destroy-dev    # or destroy-stage / destroy-prod
```

This removes: S3 buckets, KMS keys, IAM roles, monitoring node group. The EKS cluster from `enterprise-terraform-aws` remains intact.

To tear down everything including the cluster:
```bash
cd ../enterprise-terraform-aws
./scripts/destroy.sh dev
```

---

## 🎯 Interview Talking Points

This project demonstrates:

1. **Full PLT Stack** — Complete Prometheus/Loki/Tempo observability platform, not just metrics
2. **S3 Remote Storage** — Production pattern for eliminating local disk dependency in stateful workloads
3. **IRSA + Least Privilege** — Pod-level IAM without hardcoded credentials
4. **GitOps (ArgoCD)** | Declarative deployment with self-healing sync and Helm chart management
5. **Kustomize overlays** | Environment-specific customization without forking configs
6. **Multi-environment strategy** | Dev/stage/prod isolation with consistent patterns
7. **Observability correlation** | Metrics, logs, and traces share Kubernetes metadata labels
8. **Production security** | KMS encryption, IRSA, network isolation, TLS termination

**Common interview questions this can answer:**
- "How do you manage stateful workloads on EKS?" → S3 remote storage + persistent volume claims with gp3
- "How do pods access AWS services securely?" → IRSA with OIDC federation (no static credentials)
- "How do you structure observability at scale?" | PLT stack with shared labels for correlation
- "How do you manage K8s configs across environments?" | Kustomize overlays + ArgoCD GitOps
- "How do you handle log aggregation?" → FluentBit DaemonSet forwarding to Loki via S3
- "How do you correlate traces with logs and metrics?" → Shared `app`, `namespace`, `pod` labels across all three backends

---

## 📜 License

MIT — Feel free to use, modify, and showcase this in your portfolio!

---

> **Built by [Thomas Wire](https://github.com/tomwire)** — Showcasing enterprise-grade observability patterns on AWS EKS.
