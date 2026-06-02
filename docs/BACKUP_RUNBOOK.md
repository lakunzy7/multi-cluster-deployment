# Backup & Restore Runbook

## Overview

CloudOpsHub uses **Velero** for automated cluster backups. This runbook covers backup creation, restoration, and disaster recovery procedures.

## Prerequisites

- Velero CLI: `velero` command available locally
- AWS S3 bucket or compatible object storage
- Backup storage location configured (see `kubernetes/velero-install.yaml`)
- S3 credentials in `~/.aws/credentials`

## Backup Strategies

### 1. Automated Daily Backups (Scheduled)

**Default Schedule**: 2 AM UTC daily, 30-day retention

The schedule is defined in `kubernetes/velero-install.yaml`. It backs up:
- `authenticwrite` namespace (all app resources + PVs)
- `argocd` namespace (ArgoCD state)
- `monitoring` namespace (Prometheus + Grafana configs)

**Verify scheduled backup is running:**
```bash
velero schedule get
velero schedule describe daily-backup
```

### 2. Manual On-Demand Backup

Before a planned maintenance or risky change:

```bash
velero backup create backup-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces authenticwrite,argocd,monitoring
```

**Monitor backup progress:**
```bash
velero backup logs backup-20240602-120000
velero backup describe backup-20240602-120000
```

### 3. Backup Specific Resources

Backup only the app namespace (fastest):
```bash
velero backup create app-backup-$(date +%Y%m%d) \
  --include-namespaces authenticwrite
```

## Restoration Procedures

### Full Cluster Restore

After complete cluster failure:

```bash
# 1. List available backups
velero backup get

# 2. Create restore from backup
velero restore create --from-backup backup-20240601 \
  --include-namespaces authenticwrite,argocd,monitoring

# 3. Monitor restore
velero restore logs restore-20240601-000001
velero restore describe restore-20240601-000001

# 4. Verify apps are running
kubectl get pods -n authenticwrite
kubectl get pods -n argocd
```

### Partial Restore (App Namespace Only)

If only the app crashed:

```bash
velero restore create --from-backup backup-20240601 \
  --include-namespaces authenticwrite
```

### Restore to Different Cluster

1. Configure backup storage location on new cluster:
```bash
kubectl apply -f kubernetes/velero-install.yaml
```

2. Update S3 credentials if using different account.

3. Trigger restore as above.

## Disaster Recovery

### Scenario: Lost ArgoCD State

1. Restore ArgoCD namespace:
```bash
velero restore create --from-backup backup-20240601 \
  --include-namespaces argocd
```

2. Re-register clusters in ArgoCD (if cluster kubeconfigs were lost).

3. Reapply ApplicationSets:
```bash
kubectl apply -f argocd-apps/applicationset-authenticwrite.yaml
```

### Scenario: Lost PV Data (Database)

1. Check available snapshots:
```bash
velero snapshot-location get
```

2. Restore with volume snapshot:
```bash
velero restore create --from-backup backup-20240601 \
  --restore-volumes true
```

3. Verify PVCs are bound:
```bash
kubectl get pvc -n authenticwrite
```

## Backup Storage

### S3 Bucket Requirements

- **Versioning enabled** (for point-in-time recovery)
- **Lifecycle policy**: Delete old versions after 90 days (or match retention)
- **Encryption**: SSE-S3 or SSE-KMS enabled
- **Folder structure**: `s3://bucket/velero/` (Velero manages contents)

Example bucket policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::bucket-name",
        "arn:aws:s3:::bucket-name/*"
      ]
    }
  ]
}
```

## Retention & Cleanup

### Check Backup Age

```bash
velero backup get
# NAME                               STATUS      STARTED                COMPLETED              EXPIRES
# daily-backup-20240602              Completed   2024-06-02 02:00:00   2024-06-02 02:15:00   2024-07-02
```

### Manual Cleanup (if needed)

```bash
# Delete old backup (older than 30 days, typically)
velero backup delete backup-20240501 --confirm

# Resize S3 storage
aws s3 ls s3://bucket-name/velero/ --human-readable --summarize
```

## Testing Restores

**Weekly restore test** (recommended):

1. Create test cluster or namespace
2. Execute restore from most recent backup
3. Verify all apps are healthy
4. Cleanup test environment

## Monitoring

### Velero Status

```bash
kubectl get pod -n velero
kubectl logs -n velero deployment/velero --tail=50
```

### S3 Usage

```bash
aws s3 du s3://bucket-name --human-readable
```

### Failed Backups

```bash
velero backup get | grep Failed
velero backup logs <backup-name>  # see error details
```

## Troubleshooting

### Backup Stuck in "InProgress"

```bash
velero backup delete <backup-name> --confirm
# Re-run backup:
velero backup create new-backup --include-namespaces authenticwrite
```

### Restore Hangs on PVC Binding

Check PV status:
```bash
kubectl get pv
kubectl describe pv <pv-name>
```

If stuck, check storage class and node affinity.

### Credentials Error

```bash
# Verify S3 credentials are mounted
kubectl describe pod velero -n velero
# Check logs
kubectl logs -n velero deployment/velero | grep -i credential
```

## References

- [Velero Docs](https://velero.io/docs/)
- [AWS S3 Backend Guide](https://velero.io/docs/main/locations/)
- [Restore References](https://velero.io/docs/main/restore-reference/)
