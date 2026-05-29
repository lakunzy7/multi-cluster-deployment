#!/bin/bash

set -e

BACKUP_NAME=${1:-}
CLUSTER=${2:-local-cluster}

if [ -z "$BACKUP_NAME" ]; then
  echo "Usage: $0 <backup-name> [cluster]"
  echo "Available backups:"
  velero backup get --sort-by='.metadata.creationTimestamp' | tail -10
  exit 1
fi

echo "Restoring backup: $BACKUP_NAME to cluster: $CLUSTER"

# Switch to cluster
kubectl config use-context $CLUSTER

# Verify backup exists
velero backup get $BACKUP_NAME || { echo "Backup not found"; exit 1; }

# Create restore
RESTORE_NAME="${BACKUP_NAME}-restore-$(date +%Y%m%d-%H%M%S)"
velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME --wait

# Monitor restore
echo "Monitoring restore progress..."
velero restore logs $RESTORE_NAME -f

# Verify restore
echo "Restore complete!"
kubectl get all -A
