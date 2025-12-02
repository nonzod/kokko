# Volume Migration Guide

This guide provides detailed procedures for migrating all persistent volumes from `/var/lib/rancher/k3s/storage` to `/mnt/storage`.

## Overview

Currently, persistent volumes are distributed across two locations:
- `/var/lib/rancher/k3s/storage` - K3s default location (most volumes)
- `/mnt/storage` - Custom location (Home Assistant, ESPHome, WireGuard)

This migration consolidates all volumes to `/mnt/storage` for easier management and backup.

## Prerequisites

### Required Tools

- `kubectl` with cluster access
- `rsync` installed
- `jq` for JSON parsing
- Root access to the K3s host

Install missing tools:

```bash
# Install jq if not present
sudo apt-get install jq -y  # Debian/Ubuntu
sudo yum install jq -y      # RHEL/CentOS
sudo pacman -S jq           # Arch Linux
```

### Storage Requirements

Check available space on target location:

```bash
# Check current usage
sudo du -sh /var/lib/rancher/k3s/storage

# Check available space on /mnt/storage
df -h /mnt/storage

# Detailed per-volume usage
sudo du -sh /var/lib/rancher/k3s/storage/pvc-*
```

Ensure `/mnt/storage` has at least 20% more space than the total current usage to account for temporary backups.

### Pre-Migration Checklist

- [ ] Verify `/mnt/storage` exists and has sufficient space
- [ ] All cluster services are running normally
- [ ] Schedule maintenance window (expect 30-60 minutes downtime)
- [ ] Notify users of planned downtime
- [ ] Create full backup of current volumes (see below)
- [ ] Test script in dry-run mode first
- [ ] Have rollback plan ready

## Full Backup Procedure

Before starting migration, create complete backup:

```bash
# Create backup directory with timestamp
BACKUP_DIR="/backup/k3s-volumes-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

# Backup all volumes
sudo rsync -av /var/lib/rancher/k3s/storage/ "$BACKUP_DIR/k3s-storage/"
sudo rsync -av /mnt/storage/ "$BACKUP_DIR/mnt-storage/"

# Verify backup
sudo du -sh "$BACKUP_DIR"

# Save PV/PVC configuration
kubectl get pv -o yaml > "$BACKUP_DIR/pv-backup.yaml"
kubectl get pvc -A -o yaml > "$BACKUP_DIR/pvc-backup.yaml"

# Create backup manifest
cat > "$BACKUP_DIR/backup-manifest.txt" <<EOF
Backup Date: $(date)
Source Volumes: /var/lib/rancher/k3s/storage, /mnt/storage
Backup Location: $BACKUP_DIR
Total Size: $(sudo du -sh "$BACKUP_DIR" | cut -f1)
EOF

echo "Backup completed: $BACKUP_DIR"
```

## Migration Methods

### Method 1: Automated Script (Recommended)

Use the provided migration script for automated, safe migration.

#### Step 1: Dry Run

Test the migration without making changes:

```bash
cd /mnt/XFS1TB/Workspace/k3s/kokko
sudo chmod +x scripts/migrate-volumes-to-mnt-storage.sh
sudo ./scripts/migrate-volumes-to-mnt-storage.sh --dry-run
```

Review the output to verify:
- All volumes are detected correctly
- Workloads are identified properly
- No errors in prerequisites

#### Step 2: Migrate Single Volume (Test)

Test with a non-critical service first (e.g., MPD server):

```bash
# Find MPD PV name
kubectl get pv | grep mpd

# Migrate only that volume
sudo ./scripts/migrate-volumes-to-mnt-storage.sh --volume pvc-92dc134c
```

#### Step 3: Verify Test Migration

```bash
# Check PV path updated
kubectl get pv | grep mpd

# Check pod is running
kubectl get pods -n domotica | grep mpd

# Verify data integrity
kubectl exec -it -n domotica deployment/mpd-server -- ls -la /data
```

#### Step 4: Migrate All Remaining Volumes

If test successful, proceed with full migration:

```bash
sudo ./scripts/migrate-volumes-to-mnt-storage.sh
```

The script will:
1. Check prerequisites and space
2. List all volumes to migrate
3. Ask for confirmation
4. For each volume:
   - Scale down associated workload
   - Create backup
   - Copy data with rsync
   - Verify data integrity
   - Update PV path
   - Scale up workload
5. Update local-path-config ConfigMap
6. Restart local-path-provisioner

### Method 2: Manual Migration (Advanced)

For manual control or troubleshooting, follow these steps for each volume:

#### Step 1: Identify Volume

```bash
# List volumes to migrate
kubectl get pv -o custom-columns=NAME:.metadata.name,PATH:.spec.local.path | grep "/var/lib/rancher"

# Get volume details
PV_NAME="pvc-xxxxx"
kubectl get pv $PV_NAME -o yaml
```

#### Step 2: Find Associated Workload

```bash
# Get PVC info
PVC_NAME=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.claimRef.name}')
NAMESPACE=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.claimRef.namespace}')

# Find deployment using this PVC
kubectl get deployment -n $NAMESPACE -o json | \
  jq -r --arg pvc "$PVC_NAME" \
  '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name'

# Or find statefulset
kubectl get statefulset -n $NAMESPACE -o json | \
  jq -r --arg pvc "$PVC_NAME" \
  '.items[] | select(.spec.volumeClaimTemplates[]?.metadata.name == $pvc) | .metadata.name'
```

#### Step 3: Scale Down Workload

```bash
# For deployment
kubectl scale deployment <deployment-name> -n $NAMESPACE --replicas=0

# For statefulset
kubectl scale statefulset <statefulset-name> -n $NAMESPACE --replicas=0

# Verify pods terminated
kubectl get pods -n $NAMESPACE
```

#### Step 4: Copy Data

```bash
# Get current path
OLD_PATH=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.local.path}')
PVC_ID=$(basename "$OLD_PATH")
NEW_PATH="/mnt/storage/$PVC_ID"

# Create backup first
sudo rsync -av "$OLD_PATH/" "/tmp/backup-$PVC_ID/"

# Copy to new location
sudo mkdir -p "$NEW_PATH"
sudo rsync -av --delete "$OLD_PATH/" "$NEW_PATH/"

# Verify sizes match
sudo du -sb "$OLD_PATH"
sudo du -sb "$NEW_PATH"
```

#### Step 5: Update PV

```bash
# Patch PV with new path
kubectl patch pv $PV_NAME --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/spec/local/path\", \"value\": \"$NEW_PATH\"}]"

# Verify update
kubectl get pv $PV_NAME -o jsonpath='{.spec.local.path}'
```

#### Step 6: Scale Up and Verify

```bash
# Scale back up
kubectl scale deployment <deployment-name> -n $NAMESPACE --replicas=1

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=<app-name> -n $NAMESPACE --timeout=120s

# Check pod logs
kubectl logs -n $NAMESPACE deployment/<deployment-name> --tail=50

# Verify volume mount
kubectl exec -n $NAMESPACE deployment/<deployment-name> -- df -h
kubectl exec -n $NAMESPACE deployment/<deployment-name> -- ls -la /mount-path
```

#### Step 7: Repeat for All Volumes

Repeat steps 1-6 for each volume that needs migration.

## Post-Migration Steps

### Update local-path-provisioner Configuration

```bash
# Edit ConfigMap
kubectl edit configmap local-path-config -n kube-system

# Change paths from ["/var/lib/rancher/k3s/storage"] to ["/mnt/storage"]
# Save and exit

# Restart provisioner
kubectl rollout restart deployment local-path-provisioner -n kube-system
kubectl rollout status deployment local-path-provisioner -n kube-system
```

### Verify All Services

```bash
# Check all pods are running
kubectl get pods -A

# Check PV status
kubectl get pv

# Verify all volumes on new location
kubectl get pv -o custom-columns=NAME:.metadata.name,PATH:.spec.local.path

# Check persistent volume claims
kubectl get pvc -A
```

### Test Services

Test each migrated service to ensure functionality:

```bash
# Home Assistant
curl -k https://casa.nicolatomassoni.it

# ESPHome
curl -k https://esphome.nicolatomassoni.it

# Pi-hole
curl -k https://pihole.nicolatomassoni.it/admin

# Cheshire Cat
curl -k https://cat.nicolatomassoni.it/docs

# MySQL
kubectl exec -it -n db statefulset/mysql -- mysql -u root -p -e "SHOW DATABASES;"

# Qdrant
kubectl exec -it -n db statefulset/qdrant -- curl http://localhost:6333/collections
```

### Cleanup Old Data

**WARNING**: Only perform cleanup after verifying all services work correctly for several days.

```bash
# List old volume directories
sudo ls -la /var/lib/rancher/k3s/storage/pvc-*

# Before deletion, final verification
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.local.path}{"\n"}{end}' | grep -c "/var/lib/rancher"
# Should return 0

# Delete old data (BE CAREFUL!)
sudo rm -rf /var/lib/rancher/k3s/storage/pvc-*

# Keep backups for at least 30 days
ls -la /backup/
```

## Rollback Procedure

If migration fails or issues arise:

### Emergency Rollback (Per Volume)

```bash
# Scale down workload
kubectl scale deployment <deployment-name> -n $NAMESPACE --replicas=0

# Restore from backup
PVC_ID="pvc-xxxxx"
OLD_PATH="/var/lib/rancher/k3s/storage/$PVC_ID"
sudo rsync -av --delete "/tmp/backup-$PVC_ID/" "$OLD_PATH/"

# Revert PV path
kubectl patch pv $PV_NAME --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/spec/local/path\", \"value\": \"$OLD_PATH\"}]"

# Scale up workload
kubectl scale deployment <deployment-name> -n $NAMESPACE --replicas=1
```

### Full Rollback

```bash
# Restore all PV configurations
kubectl apply -f "$BACKUP_DIR/pv-backup.yaml"

# Restore all volumes
sudo rsync -av --delete "$BACKUP_DIR/k3s-storage/" /var/lib/rancher/k3s/storage/
sudo rsync -av --delete "$BACKUP_DIR/mnt-storage/" /mnt/storage/

# Restart all deployments
kubectl rollout restart deployment -A
kubectl rollout restart statefulset -A

# Verify
kubectl get pods -A
```

## Troubleshooting

### Volume Not Mounting

```bash
# Check PV status
kubectl describe pv <pv-name>

# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Verify path exists on host
sudo ls -la /mnt/storage/<pvc-id>
```

### Permission Issues

```bash
# Check ownership
sudo ls -la /mnt/storage/<pvc-id>

# Fix permissions (adjust UID/GID as needed)
sudo chown -R 1000:1000 /mnt/storage/<pvc-id>
```

### Data Corruption

```bash
# Stop workload immediately
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0

# Restore from backup
sudo rsync -av --delete "/tmp/backup-<pvc-id>/" "/mnt/storage/<pvc-id>/"

# Restart workload
kubectl scale deployment <deployment-name> -n <namespace> --replicas=1
```

### Pod Stuck in Pending

```bash
# Check PVC binding
kubectl get pvc -n <namespace>

# Check PV available
kubectl get pv

# Delete and recreate pod (not PVC!)
kubectl delete pod <pod-name> -n <namespace>
```

## Migration Sequence Recommendation

Recommended order to minimize risk:

1. **Test volume** (mpd-server) - Non-critical, small
2. **Wyoming Piper** - Small, easily replaceable
3. **Samba** - No persistent state, just shares HA volume
4. **Pi-hole DNS** - Can tolerate brief outage
5. **Qdrant** - Database, but can be rebuilt
6. **MySQL** - Critical, backup carefully
7. **Cheshire Cat** - Depends on Qdrant
8. **ESPHome** - Already on /mnt/storage (verify only)
9. **Home Assistant** - Already on /mnt/storage (verify only)
10. **WireGuard** - Already on /mnt/storage (verify only)

## Expected Downtime

Per service:
- Small volumes (<1GB): 2-5 minutes
- Medium volumes (1-10GB): 5-15 minutes
- Large volumes (>10GB): 15-30 minutes

Total migration time: 30-60 minutes depending on data size.

## Best Practices

1. **Perform during maintenance window**: Schedule for low-traffic period
2. **Test first**: Always use --dry-run and test with non-critical service
3. **Verify backups**: Ensure backups are complete before starting
4. **Monitor closely**: Watch pod logs during and after migration
5. **Keep backups**: Retain backups for at least 30 days
6. **Document changes**: Note migration date and any issues encountered
7. **Update monitoring**: Update any backup scripts or monitoring that reference old paths

## References

- [STORAGE.md](STORAGE.md) - Storage management procedures
- Migration script: `scripts/migrate-volumes-to-mnt-storage.sh`
- Log files: `/tmp/volume-migration-*.log`
