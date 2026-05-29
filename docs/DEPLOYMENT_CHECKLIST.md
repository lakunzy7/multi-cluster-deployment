# CloudOpsHub Deployment Checklist

## Pre-Deployment Checklist

### GCP Setup
- [ ] GCP project created
- [ ] Billing enabled
- [ ] APIs enabled (compute, container, sqladmin, storage, servicenetworking, secretmanager)
- [ ] gcloud CLI installed and authenticated
- [ ] gcloud project set to correct project

### Local Machine Setup
- [ ] Terraform >= 1.0 installed
- [ ] kubectl >= 1.28 installed
- [ ] Helm 3 installed
- [ ] Docker installed
- [ ] Kind or k3s installed (for local cluster)
- [ ] Git configured

### Credentials & Access
- [ ] GCP service account created (if needed)
- [ ] Docker Hub/Registry credentials available
- [ ] SSH keys generated (if using custom VMs)
- [ ] GitLab/GitHub access token created

## Deployment Checklist

### Phase 1: Infrastructure (10-15 minutes)
- [ ] Clone/copy project to working directory
- [ ] Create `terraform/terraform.tfvars` from example
- [ ] Run `terraform init`
- [ ] Run `terraform plan` and review
- [ ] Run `terraform apply`
- [ ] Save Terraform outputs
- [ ] Verify GKE cluster created: `gcloud container clusters list`
- [ ] Verify Cloud SQL created: `gcloud sql instances list`

### Phase 2: Local Cluster Setup (5 minutes)
- [ ] Create local cluster with Kind: `kind create cluster --name local-cluster`
- [ ] OR install k3s: `curl -sfL https://get.k3s.io | sh -`
- [ ] Verify local cluster accessible: `kubectl cluster-info --context kind-local-cluster`
- [ ] Configure kubeconfig with both clusters

### Phase 3: Kubernetes Configuration (5 minutes)
- [ ] Apply namespaces: `kubectl apply -f kubernetes/namespaces.yml`
- [ ] Apply storage classes: `kubectl apply -f kubernetes/storage-class.yml`
- [ ] Apply network policies: `kubectl apply -f kubernetes/network-policies.yml`
- [ ] Verify namespaces created: `kubectl get namespaces`

### Phase 4: Monitoring Stack (5 minutes)
- [ ] Add Prometheus Helm repo
- [ ] Add Grafana Helm repo
- [ ] Add Loki Helm repo
- [ ] Install Prometheus: `helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace`
- [ ] Install Loki: `helm install loki grafana/loki-stack -n logging --create-namespace`
- [ ] Verify monitoring pods running: `kubectl get pods -n monitoring`

### Phase 5: ArgoCD Setup (10 minutes)
- [ ] Add ArgoCD Helm repo
- [ ] Install ArgoCD: `helm install argocd argo/argo-cd -n argocd --create-namespace`
- [ ] Get ArgoCD admin password
- [ ] Port-forward to ArgoCD: `kubectl port-forward -n argocd svc/argocd-server 8080:443`
- [ ] Login to ArgoCD UI (https://localhost:8080)
- [ ] Configure cloud cluster credentials in ArgoCD
- [ ] Apply ArgoCD applications: `kubectl apply -f kubernetes/argocd-applications.yml`
- [ ] Verify applications syncing: `argocd app list`

### Phase 6: Application Deployment (5 minutes)
- [ ] Create Git repository for application manifests
- [ ] Push application manifests to Git
- [ ] Update ArgoCD application source repository URL
- [ ] Trigger ArgoCD sync: `argocd app sync analytics-platform-dev`
- [ ] Verify pods deployed: `kubectl get pods -n dev`
- [ ] Test application endpoints

### Phase 7: CI/CD Pipeline Setup (Optional)
- [ ] Create GitLab/GitHub project for application code
- [ ] Create repository variables (DOCKER_USERNAME, DOCKER_PASSWORD)
- [ ] Push sample Dockerfile and application code
- [ ] Trigger CI pipeline
- [ ] Verify image pushed to registry
- [ ] Verify deployment to dev cluster

## Post-Deployment Verification

### Cluster Health
- [ ] All nodes ready: `kubectl get nodes`
- [ ] All pods running: `kubectl get pods -A`
- [ ] No pending pods: `kubectl get pods -A --field-selector=status.phase=Pending`
- [ ] No failed pods: `kubectl get pods -A --field-selector=status.phase=Failed`

### Services Access
- [ ] Prometheus accessible: `http://localhost:9090`
- [ ] Grafana accessible: `http://localhost:3000`
- [ ] ArgoCD accessible: `https://localhost:8080`
- [ ] Applications accessible via ingress/service

### Database
- [ ] Cloud SQL instance healthy: `gcloud sql instances describe cloudopshub-postgres`
- [ ] Database created: `psql -h <ip> -U admin -d cloudopshub`
- [ ] Application can connect to database

### Monitoring
- [ ] Prometheus scraping targets: All "UP"
- [ ] Grafana datasources configured
- [ ] Loki receiving logs
- [ ] Alertmanager configured

### Backups
- [ ] Test Velero backup: `velero backup create test-backup`
- [ ] Verify backup completed: `velero backup get`
- [ ] Test Cloud SQL backup exists

## Operational Verification

### Deployment
- [ ] Can deploy to dev environment
- [ ] Can manually deploy to staging
- [ ] Can manually deploy to production
- [ ] Rollback works: `kubectl rollout undo deployment/...`

### Monitoring
- [ ] Can access Prometheus dashboards
- [ ] Can view pod logs in Loki
- [ ] Can view traces in Jaeger
- [ ] Alerts fire on test conditions

### Backup & Recovery
- [ ] Can create manual backup
- [ ] Can list backups
- [ ] Recovery procedure documented
- [ ] Point-in-time recovery tested

## Security Verification

- [ ] Network policies enforce pod communication
- [ ] Secrets not stored in Git
- [ ] Cloud SQL uses private endpoint
- [ ] RBAC configured for service accounts
- [ ] Audit logging enabled

## Documentation Verification

- [ ] SETUP.md follows all steps without errors
- [ ] ARCHITECTURE.md accurately describes deployed system
- [ ] DEPLOYMENT_RUNBOOK.md covers all operational procedures
- [ ] MONITORING_RUNBOOK.md documents all dashboards
- [ ] All scripts (deploy.sh, backup.sh, restore.sh) executable and working

## Final Checklist

- [ ] All infrastructure deployed and verified
- [ ] All applications running in all environments
- [ ] Monitoring and logging operational
- [ ] Backups created and verified
- [ ] Documentation complete and accurate
- [ ] Team trained on operational procedures
- [ ] Runbooks tested and verified
- [ ] Incident response procedures documented
- [ ] Security review completed
- [ ] Cost optimization review completed

## Rollback Steps (If Needed)

If any step fails:

1. **Infrastructure Issue**
   ```bash
   terraform destroy
   # Fix issue
   terraform apply
   ```

2. **Kubernetes Configuration Issue**
   ```bash
   kubectl delete namespace dev staging production
   kubectl apply -f kubernetes/
   ```

3. **Helm Release Issue**
   ```bash
   helm uninstall <release> -n <namespace>
   helm install <release> <chart> -n <namespace>
   ```

4. **Application Issue**
   ```bash
   argocd app delete <app-name>
   # Fix Git repository
   argocd app create <app-name> ...
   ```

## Support Resources

- **Terraform Docs**: https://registry.terraform.io/providers/hashicorp/google/latest/docs
- **GKE Docs**: https://cloud.google.com/kubernetes-engine/docs
- **Kubernetes Docs**: https://kubernetes.io/docs
- **ArgoCD Docs**: https://argo-cd.readthedocs.io
- **Prometheus Docs**: https://prometheus.io/docs
- **Grafana Docs**: https://grafana.com/docs
- **Project Documentation**: See `docs/` directory

## Notes

Use this checklist to track deployment progress and ensure nothing is missed.

**Estimated Total Time: 45-60 minutes**

Date: _______________
Completed By: _______________
Verified By: _______________
