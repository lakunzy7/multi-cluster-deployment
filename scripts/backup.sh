#!/bin/bash

set -e

CLUSTER=${1:-local-cluster}
BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)"

echo "Creating backup: $BACKUP_NAME for cluster: $CLUSTER"

# Switch to cluster
kubectl config use-context $CLUSTER

# Create namespace backup
velero backup create $BACKUP_NAME \
  --include-namespaces '*' \
  --wait

# Backup RDS database
echo "Creating RDS snapshot..."
SNAPSHOT_ID="${BACKUP_NAME}-rds"
aws rds create-db-snapshot \
  --db-instance-identifier cloudopshub-postgres \
  --db-snapshot-identifier $SNAPSHOT_ID

# Wait for snapshot completion
aws rds wait db-snapshot-available \
  --db-snapshot-identifier $SNAPSHOT_ID

echo "Backup complete: $BACKUP_NAME"
echo "RDS Snapshot: $SNAPSHOT_ID"

# List recent backups
velero backup get --sort-by='.metadata.creationTimestamp' | head -5
