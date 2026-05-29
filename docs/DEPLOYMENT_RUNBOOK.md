# Deployment Runbook

## Pre-Deployment Checklist

- [ ] Git branch is up-to-date with main
- [ ] All tests pass locally
- [ ] Code review approved
- [ ] Security scanning passed
- [ ] Target environment namespace exists
- [ ] Sufficient cluster resources available

## Development Deployment

### Automated Flow
```bash
# Push to develop branch
git push origin feature-branch:develop

# GitLab CI pipeline automatically:
# 1. Builds Docker image
# 2. Runs security scans
# 3. Pushes to registry
# 4. Deploys to dev cluster
```

### Manual Deployment
```bash
# Switch to dev context
kubectl config use-context local-cluster

# Apply manifests
kubectl apply -f k8s/dev/ -n dev

# Verify deployment
kubectl rollout status deployment/analytics-platform -n dev

# Check logs
kubectl logs -n dev -l app=analytics-platform -f
```

## Staging Deployment

### Prerequisites
- Dev deployment successful
- QA testing approved
- Staging snapshot ready

### Procedure
```bash
# Merge to main branch
git checkout main
git pull origin main

# Manual approval in GitLab CI (required)
# Pipeline runs staging deployment job

# Verify in staging
kubectl config use-context local-cluster
kubectl get deployments -n staging
kubectl get pods -n staging
kubectl logs -n staging -l app=analytics-platform
```

## Production Deployment

### Prerequisites
- Staging environment tested and approved
- Product owner sign-off
- On-call engineer available
- Rollback plan reviewed

### Procedure
```bash
# Create release tag
git tag v1.0.0
git push origin v1.0.0

# Manual approval in GitLab CI (required)
# Pipeline deploys to prod (cloud-eks)

# Verify production
kubectl config use-context cloud-cluster
kubectl get deployments -n production
kubectl get pods -n production

# Monitor metrics
# Dashboard: http://grafana:3000 (production-overview)
```

## Rollback Procedures

### Rollback to Previous Version
```bash
# Check rollout history
kubectl rollout history deployment/analytics-platform -n production

# Rollout to previous version
kubectl rollout undo deployment/analytics-platform -n production

# Verify rollback
kubectl rollout status deployment/analytics-platform -n production
kubectl get pods -n production
```

### Rollback via ArgoCD
```bash
# View sync history
argocd app history analytics-platform

# Rollback to specific revision
argocd app rollback analytics-platform <revision>

# Monitor sync
argocd app wait analytics-platform
```

### Rollback via Git
```bash
# Revert commit
git revert <commit-hash>
git push origin main

# ArgoCD auto-syncs or manual sync:
argocd app sync analytics-platform
```

## Canary Deployments

```bash
# Deploy new version to subset of pods
kubectl patch deployment/analytics-platform -n production -p \
  '{"spec":{"replicas":5}}'

# Scale canary replicas to test
kubectl set image deployment/analytics-platform \
  -n production \
  analytics=docker.io/cloudopshub/analytics-platform:v1.1.0 \
  --record

# Monitor canary
kubectl logs -n production -l app=analytics-platform -f

# If successful, scale up remaining pods
kubectl rollout status deployment/analytics-platform -n production

# If failed, rollback
kubectl rollout undo deployment/analytics-platform -n production
```

## Blue-Green Deployments

```bash
# Deploy new version (green) alongside current (blue)
kubectl apply -f k8s/prod/blue-green.yml

# Test green version
kubectl exec -it deployment/analytics-platform-green -n production -- /bin/bash

# Switch traffic to green
kubectl patch service analytics-platform -n production \
  -p '{"spec":{"selector":{"version":"green"}}}'

# Monitor traffic
kubectl logs -n production -l app=analytics-platform,version=green -f

# If successful, delete blue deployment
kubectl delete deployment analytics-platform-blue -n production
```

## Troubleshooting During Deployment

### Pods not starting
```bash
# Check pod events
kubectl describe pod <pod-name> -n production

# Check resource limits
kubectl top pods -n production
kubectl top nodes

# Check image availability
kubectl get events -n production --sort-by='.lastTimestamp'
```

### Image pull errors
```bash
# Verify image exists in registry
docker pull docker.io/cloudopshub/analytics-platform:v1.0.0

# Check image pull secrets
kubectl get secrets -n production
kubectl describe secret regcred -n production
```

### Persistent volume issues
```bash
# Check PVC status
kubectl get pvc -n production
kubectl describe pvc <pvc-name> -n production

# Check PV status
kubectl get pv
kubectl describe pv <pv-name>
```

### DNS resolution issues
```bash
# Test DNS from pod
kubectl exec -it <pod-name> -n production -- nslookup kubernetes.default

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
```

## Post-Deployment Validation

```bash
# Health check
curl -s https://<service-endpoint>/health | jq .

# Database connectivity
kubectl exec -it <pod-name> -n production -- psql -h <db-host> -U admin -d cloudopshub -c "SELECT 1"

# Log aggregation
# Check Grafana Loki dashboard for errors

# Metrics collection
# Verify metrics in Prometheus: http://prometheus:9090

# Alert status
# Check if any new alerts fired in Alertmanager
```

## Incident Response

### Service down
```bash
# Check pod status
kubectl get pods -n production --field-selector=status.phase!=Running

# Check node status
kubectl get nodes

# Check recent events
kubectl get events -n production --sort-by='.lastTimestamp'

# Check logs for errors
kubectl logs -n production -l app=analytics-platform --tail=100 | grep ERROR
```

### High latency
```bash
# Check resource utilization
kubectl top nodes
kubectl top pods -n production

# Check service endpoints
kubectl get endpoints analytics-platform -n production

# Check network policies
kubectl get networkpolicies -n production
```

### Database issues
```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier cloudopshub-postgres

# Check database logs
aws rds describe-db-log-files --db-instance-identifier cloudopshub-postgres

# Check database connections
kubectl exec -it <pod-name> -n production -- psql -h <db-host> -U admin -d cloudopshub -c "SELECT count(*) FROM pg_stat_activity"
```

## Communication

- **Deployment start**: Notify team in #deployments Slack channel
- **Deployment complete**: Post status with metrics (response time, error rate)
- **Issues encountered**: Create incident post in #incidents channel
- **Rollback executed**: Post root cause analysis link and timeline
