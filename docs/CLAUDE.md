# CloudOpsHub: Automated Multi-Cluster Infrastructure Platform

DevOps automation platform for provisioning and managing multi-cluster Kubernetes infrastructure with continuous delivery and centralized observability.

## Stack
- **IaC**: Terraform (cloud infrastructure provisioning)
- **Cloud Provider**: Google Cloud Platform (GCP)
- **Configuration Management**: Ansible (post-provisioning configuration)
- **Container Orchestration**: Kubernetes (local cluster + GKE cloud cluster)
- **Continuous Delivery**: ArgoCD (single centralized CD managing all clusters)
- **Managed Database**: Cloud SQL (PostgreSQL)
- **Monitoring**: Prometheus + Grafana (metrics), Loki (logs), Jaeger (tracing)
- **CI/CD**: GitLab CI / GitHub Actions (container builds, vulnerability scanning)

## Key Commands
- `terraform init && terraform plan && terraform apply` — Provision infrastructure
- `ansible-playbook site.yml` — Configure servers post-provisioning
- `kubectl apply -f <manifests>` — Deploy to Kubernetes clusters
- `argocd app create` — Register applications with ArgoCD
- `docker build` — Build containerized applications

## Architecture
- `terraform/` — Terraform configurations for multi-cluster setup (local + cloud clusters, networking, supporting infra)
- `ansible/` — Ansible playbooks for server configuration and cluster setup
- `kubernetes/` — Kubernetes manifests, ArgoCD applications, multi-cluster configurations
- `ci-cd/` — CI/CD pipeline definitions (GitLab CI / GitHub Actions)
- `monitoring/` — Prometheus, Grafana dashboards, alerting rules, log aggregation configs
- `scripts/` — Utility scripts for deployment, backup, recovery, troubleshooting
- `docs/` — Architecture diagrams, runbooks, setup documentation, troubleshooting guides

## Key Files
- `Project.md` — Business requirements and deliverables for the platform
- `terraform/main.tf` — Primary Terraform configuration (entry point)
- `kubernetes/argocd/` — ArgoCD applications for centralized CD
- `ci-cd/pipeline.yml` — CI/CD pipeline definitions
- `monitoring/prometheus.yml` — Prometheus configuration
- `docs/ARCHITECTURE.md` — System design and component interaction
- `docs/SETUP.md` — Step-by-step deployment instructions

## Preferences
- Minimal output, lead with the answer
- Plain code snippets over interactive artifacts
- Use offset/limit when reading files; never re-read entire files
- No Co-Authored-By in commits
- Concise responses, no filler

## Session Log
- 2026-05-26: Project structure initialized, base directories created, task breakdown established
