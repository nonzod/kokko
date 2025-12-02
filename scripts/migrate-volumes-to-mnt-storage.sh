#!/bin/bash
set -e

# Volume Migration Script
# Migrates all PVs from /var/lib/rancher/k3s/storage to /mnt/storage
#
# Usage: sudo ./migrate-volumes-to-mnt-storage.sh [--dry-run] [--volume pvc-xxx]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/volume-migration-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
SPECIFIC_VOLUME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --volume)
            SPECIFIC_VOLUME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--volume pvc-xxx]"
            exit 1
            ;;
    esac
done

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check if /mnt/storage exists
    if [ ! -d "/mnt/storage" ]; then
        log_error "/mnt/storage directory does not exist"
        read -p "Do you want to create it? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p /mnt/storage
            chmod 755 /mnt/storage
            log_success "Created /mnt/storage directory"
        else
            exit 1
        fi
    fi

    # Check available space
    local source_usage=$(du -sb /var/lib/rancher/k3s/storage 2>/dev/null | cut -f1)
    local target_available=$(df -B1 /mnt/storage | tail -1 | awk '{print $4}')

    if [ "$source_usage" -gt "$target_available" ]; then
        log_error "Not enough space on /mnt/storage"
        log_error "Required: $(numfmt --to=iec $source_usage), Available: $(numfmt --to=iec $target_available)"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

get_volumes_to_migrate() {
    if [ -n "$SPECIFIC_VOLUME" ]; then
        kubectl get pv -o json | jq -r --arg vol "$SPECIFIC_VOLUME" \
            '.items[] | select(.spec.local.path | contains("/var/lib/rancher/k3s/storage")) | select(.metadata.name | contains($vol)) | .metadata.name'
    else
        kubectl get pv -o json | jq -r \
            '.items[] | select(.spec.local.path | contains("/var/lib/rancher/k3s/storage")) | .metadata.name'
    fi
}

get_pv_info() {
    local pv_name=$1
    kubectl get pv "$pv_name" -o json
}

get_workload_for_pvc() {
    local pvc_name=$1
    local namespace=$2

    # Try to find deployment
    local deployment=$(kubectl get deployment -n "$namespace" -o json | \
        jq -r --arg pvc "$pvc_name" \
        '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' | head -1)

    if [ -n "$deployment" ]; then
        echo "deployment/$deployment"
        return
    fi

    # Try to find statefulset
    local statefulset=$(kubectl get statefulset -n "$namespace" -o json | \
        jq -r --arg pvc "$pvc_name" \
        '.items[] | select(.spec.volumeClaimTemplates[]?.metadata.name == $pvc or .spec.template.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' | head -1)

    if [ -n "$statefulset" ]; then
        echo "statefulset/$statefulset"
        return
    fi

    echo ""
}

scale_workload() {
    local workload=$1
    local namespace=$2
    local replicas=$3

    if [ -z "$workload" ]; then
        log_warning "No workload found to scale"
        return 0
    fi

    log "Scaling $workload in namespace $namespace to $replicas replicas..."
    kubectl scale "$workload" -n "$namespace" --replicas="$replicas"

    if [ "$replicas" -eq 0 ]; then
        log "Waiting for pods to terminate..."
        sleep 10
    else
        log "Waiting for pods to be ready..."
        local workload_type=$(echo "$workload" | cut -d'/' -f1)
        local workload_name=$(echo "$workload" | cut -d'/' -f2)
        kubectl wait --for=condition=available --timeout=300s "$workload_type/$workload_name" -n "$namespace" || true
    fi
}

migrate_volume() {
    local pv_name=$1

    log "=========================================="
    log "Processing PV: $pv_name"

    local pv_info=$(get_pv_info "$pv_name")
    local old_path=$(echo "$pv_info" | jq -r '.spec.local.path')
    local pvc_name=$(echo "$pv_info" | jq -r '.spec.claimRef.name')
    local namespace=$(echo "$pv_info" | jq -r '.spec.claimRef.namespace')
    local status=$(echo "$pv_info" | jq -r '.status.phase')

    # Extract PVC ID from path
    local pvc_id=$(basename "$old_path")
    local new_path="/mnt/storage/$pvc_id"

    log "PV: $pv_name"
    log "PVC: $pvc_name"
    log "Namespace: $namespace"
    log "Status: $status"
    log "Old path: $old_path"
    log "New path: $new_path"

    # Check if already migrated
    if [[ "$old_path" == "/mnt/storage/"* ]]; then
        log_success "Volume already on /mnt/storage, skipping"
        return 0
    fi

    # Check if source exists
    if [ ! -d "$old_path" ]; then
        log_error "Source path does not exist: $old_path"
        return 1
    fi

    # Find associated workload
    local workload=$(get_workload_for_pvc "$pvc_name" "$namespace")
    log "Associated workload: ${workload:-none}"

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would migrate $old_path -> $new_path"
        return 0
    fi

    # Scale down workload
    if [ -n "$workload" ]; then
        scale_workload "$workload" "$namespace" 0
    fi

    # Create backup
    local backup_path="/tmp/backup-$pvc_id-$(date +%Y%m%d-%H%M%S)"
    log "Creating backup at $backup_path..."
    rsync -av "$old_path/" "$backup_path/" >> "$LOG_FILE" 2>&1
    log_success "Backup created"

    # Copy data to new location
    log "Copying data to $new_path..."
    mkdir -p "$new_path"
    rsync -av --delete "$old_path/" "$new_path/" >> "$LOG_FILE" 2>&1

    # Verify copy
    local old_size=$(du -sb "$old_path" | cut -f1)
    local new_size=$(du -sb "$new_path" | cut -f1)

    if [ "$old_size" -ne "$new_size" ]; then
        log_error "Size mismatch! Old: $old_size, New: $new_size"
        log_error "Restoring from backup..."
        rm -rf "$new_path"
        return 1
    fi

    log_success "Data copied successfully ($(numfmt --to=iec $new_size))"

    # Update PV path
    log "Updating PV path..."
    kubectl patch pv "$pv_name" --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/local/path\", \"value\": \"$new_path\"}]"

    # Verify PV update
    sleep 2
    local updated_path=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.local.path}')
    if [ "$updated_path" != "$new_path" ]; then
        log_error "Failed to update PV path"
        return 1
    fi

    log_success "PV path updated"

    # Scale up workload
    if [ -n "$workload" ]; then
        scale_workload "$workload" "$namespace" 1

        # Wait and verify pod is running
        sleep 10
        local pod_status=$(kubectl get pods -n "$namespace" -l app=$(echo "$workload" | cut -d'/' -f2) -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

        if [ "$pod_status" != "Running" ]; then
            log_warning "Pod not running yet, status: $pod_status"
            log_warning "Check manually: kubectl get pods -n $namespace"
        else
            log_success "Pod is running"
        fi
    fi

    # Keep backup for safety
    log "Backup preserved at: $backup_path"
    log_success "Migration completed for $pv_name"

    return 0
}

update_local_path_config() {
    log "=========================================="
    log "Updating local-path-config ConfigMap..."

    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would update local-path-config to use /mnt/storage"
        return 0
    fi

    kubectl patch configmap local-path-config -n kube-system --type='json' \
        -p='[{"op": "replace", "path": "/data/config.json", "value": "{\n  \"nodePathMap\":[\n  {\n    \"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\n    \"paths\":[\"/mnt/storage\"]\n  }\n  ]\n}"}]'

    log "Restarting local-path-provisioner..."
    kubectl rollout restart deployment local-path-provisioner -n kube-system
    kubectl rollout status deployment local-path-provisioner -n kube-system --timeout=60s

    log_success "local-path-provisioner configuration updated"
}

main() {
    log "=========================================="
    log "Volume Migration Script"
    log "Log file: $LOG_FILE"

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    check_prerequisites

    log "=========================================="
    log "Finding volumes to migrate..."

    local volumes=$(get_volumes_to_migrate)
    local volume_count=$(echo "$volumes" | wc -l)

    if [ -z "$volumes" ]; then
        log_success "No volumes to migrate!"
        update_local_path_config
        exit 0
    fi

    log "Found $volume_count volume(s) to migrate:"
    echo "$volumes" | while read pv; do
        log "  - $pv"
    done

    if [ "$DRY_RUN" = false ]; then
        log "=========================================="
        log_warning "This will migrate $volume_count volume(s) and cause service downtime"
        read -p "Continue? (yes/no) " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            log "Migration cancelled"
            exit 0
        fi
    fi

    # Migrate each volume
    local success_count=0
    local fail_count=0

    echo "$volumes" | while read pv; do
        if migrate_volume "$pv"; then
            ((success_count++))
        else
            ((fail_count++))
            log_error "Failed to migrate $pv"
        fi
    done

    log "=========================================="
    log "Migration Summary"
    log "Successful: $success_count"
    log "Failed: $fail_count"

    if [ $fail_count -eq 0 ] && [ "$DRY_RUN" = false ]; then
        update_local_path_config
    fi

    log "=========================================="
    log "Migration completed"
    log "Log file: $LOG_FILE"

    if [ $fail_count -gt 0 ]; then
        exit 1
    fi
}

main
