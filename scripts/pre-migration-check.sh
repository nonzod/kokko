#!/bin/bash

# Pre-Migration Checklist Script
# Verifies system is ready for volume migration
#
# Usage: ./pre-migration-check.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_COUNT++))
}

print_header "Pre-Migration Checklist"

echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Check 1: Root access
print_header "1. System Access"
if [ "$EUID" -eq 0 ]; then
    check_pass "Running as root"
else
    check_fail "Not running as root (use sudo)"
fi

# Check 2: Required tools
print_header "2. Required Tools"

if command -v kubectl &> /dev/null; then
    check_pass "kubectl is installed"
    kubectl version --client --short 2>/dev/null || echo "  Version check skipped"
else
    check_fail "kubectl not found"
fi

if command -v rsync &> /dev/null; then
    check_pass "rsync is installed"
    rsync --version | head -1
else
    check_fail "rsync not found"
fi

if command -v jq &> /dev/null; then
    check_pass "jq is installed"
    jq --version
else
    check_fail "jq not found - install with: sudo apt-get install jq"
fi

# Check 3: Kubernetes cluster access
print_header "3. Cluster Access"

if kubectl cluster-info &> /dev/null; then
    check_pass "Can access Kubernetes cluster"
    kubectl get nodes --no-headers | while read line; do
        echo "  Node: $line"
    done
else
    check_fail "Cannot access Kubernetes cluster"
fi

# Check 4: Storage paths
print_header "4. Storage Paths"

if [ -d "/var/lib/rancher/k3s/storage" ]; then
    check_pass "Source path exists: /var/lib/rancher/k3s/storage"
    SOURCE_SIZE=$(du -sb /var/lib/rancher/k3s/storage 2>/dev/null | cut -f1)
    echo "  Size: $(numfmt --to=iec $SOURCE_SIZE)"
else
    check_warn "Source path does not exist (no volumes to migrate?)"
    SOURCE_SIZE=0
fi

if [ -d "/mnt/storage" ]; then
    check_pass "Target path exists: /mnt/storage"
else
    check_warn "Target path does not exist (/mnt/storage)"
    read -p "  Create /mnt/storage? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p /mnt/storage
        chmod 755 /mnt/storage
        check_pass "Created /mnt/storage"
    else
        check_fail "Target path must exist before migration"
    fi
fi

# Check 5: Available space
print_header "5. Storage Capacity"

if [ -d "/mnt/storage" ]; then
    TARGET_AVAIL=$(df -B1 /mnt/storage | tail -1 | awk '{print $4}')
    TARGET_TOTAL=$(df -B1 /mnt/storage | tail -1 | awk '{print $2}')
    TARGET_USED=$(df -B1 /mnt/storage | tail -1 | awk '{print $3}')

    echo "Target filesystem (/mnt/storage):"
    echo "  Total: $(numfmt --to=iec $TARGET_TOTAL)"
    echo "  Used: $(numfmt --to=iec $TARGET_USED)"
    echo "  Available: $(numfmt --to=iec $TARGET_AVAIL)"

    if [ $SOURCE_SIZE -gt 0 ]; then
        REQUIRED_SPACE=$((SOURCE_SIZE + SOURCE_SIZE / 5))  # Add 20% buffer
        echo ""
        echo "Source size: $(numfmt --to=iec $SOURCE_SIZE)"
        echo "Required (with 20% buffer): $(numfmt --to=iec $REQUIRED_SPACE)"

        if [ $TARGET_AVAIL -gt $REQUIRED_SPACE ]; then
            check_pass "Sufficient space available"
            SPACE_AFTER=$((TARGET_AVAIL - SOURCE_SIZE))
            echo "  Space after migration: $(numfmt --to=iec $SPACE_AFTER)"
        else
            check_fail "Insufficient space on /mnt/storage"
            SPACE_NEEDED=$((REQUIRED_SPACE - TARGET_AVAIL))
            echo "  Need additional: $(numfmt --to=iec $SPACE_NEEDED)"
        fi
    else
        check_warn "Cannot calculate space requirements (no source volumes)"
    fi
else
    check_fail "Cannot check space - /mnt/storage does not exist"
fi

# Check 6: Volumes to migrate
print_header "6. Volumes to Migrate"

VOLUMES_TO_MIGRATE=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.local.path | contains("/var/lib/rancher/k3s/storage")) | .metadata.name' || echo "")

if [ -z "$VOLUMES_TO_MIGRATE" ]; then
    check_warn "No volumes found to migrate"
    VOLUME_COUNT=0
else
    VOLUME_COUNT=$(echo "$VOLUMES_TO_MIGRATE" | wc -l)
    check_pass "Found $VOLUME_COUNT volume(s) to migrate"
    echo ""
    echo "Volumes:"
    echo "$VOLUMES_TO_MIGRATE" | while read pv; do
        PVC_NAME=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef.name}' 2>/dev/null)
        NAMESPACE=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef.namespace}' 2>/dev/null)
        PV_PATH=$(kubectl get pv "$pv" -o jsonpath='{.spec.local.path}' 2>/dev/null)
        PV_SIZE=$(du -sh "$PV_PATH" 2>/dev/null | cut -f1 || echo "N/A")
        echo "  - $pv"
        echo "    PVC: $PVC_NAME (namespace: $NAMESPACE)"
        echo "    Size: $PV_SIZE"
    done
fi

# Check 7: Pod status
print_header "7. Cluster Health"

TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo 0)
PROBLEM_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo 0)

echo "Cluster pods:"
echo "  Total: $TOTAL_PODS"
echo "  Running: $RUNNING_PODS"
echo "  Not Running: $PROBLEM_PODS"

if [ $PROBLEM_PODS -eq 0 ]; then
    check_pass "All pods are healthy"
else
    check_warn "Some pods are not running - investigate before migration"
    echo ""
    echo "Problem pods:"
    kubectl get pods -A --no-headers | grep -v "Running\|Completed" || true
fi

# Check 8: Recent backups
print_header "8. Backup Status"

BACKUP_LOCATIONS=(
    "/backup"
    "/tmp/backup"
    "/mnt/backup"
)

FOUND_BACKUP=false
for backup_dir in "${BACKUP_LOCATIONS[@]}"; do
    if [ -d "$backup_dir" ]; then
        RECENT_BACKUPS=$(find "$backup_dir" -type d -name "k3s-volumes-*" -mtime -7 2>/dev/null || true)
        if [ -n "$RECENT_BACKUPS" ]; then
            check_pass "Found recent backup in $backup_dir"
            echo "$RECENT_BACKUPS" | while read backup; do
                echo "  - $backup ($(du -sh "$backup" 2>/dev/null | cut -f1))"
            done
            FOUND_BACKUP=true
        fi
    fi
done

if [ "$FOUND_BACKUP" = false ]; then
    check_fail "No recent backups found in common locations"
    echo "  Create backup before migration with:"
    echo "  sudo rsync -av /var/lib/rancher/k3s/storage/ /backup/k3s-volumes-\$(date +%Y%m%d)/"
fi

# Check 9: Migration script
print_header "9. Migration Script"

SCRIPT_PATH="$(dirname "$0")/migrate-volumes-to-mnt-storage.sh"
if [ -f "$SCRIPT_PATH" ]; then
    check_pass "Migration script found: $SCRIPT_PATH"
    if [ -x "$SCRIPT_PATH" ]; then
        check_pass "Migration script is executable"
    else
        check_warn "Migration script is not executable"
        echo "  Run: chmod +x $SCRIPT_PATH"
    fi
else
    check_fail "Migration script not found at $SCRIPT_PATH"
fi

# Check 10: System load
print_header "10. System Resources"

LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
CPU_COUNT=$(nproc)
MEM_TOTAL=$(free -b | awk '/^Mem:/{print $2}')
MEM_AVAIL=$(free -b | awk '/^Mem:/{print $7}')
MEM_PERCENT=$(awk "BEGIN {printf \"%.0f\", ($MEM_AVAIL / $MEM_TOTAL) * 100}")

echo "System load:"
echo "  Load average: $LOAD_AVG (CPUs: $CPU_COUNT)"
echo "  Memory available: $(numfmt --to=iec $MEM_AVAIL) / $(numfmt --to=iec $MEM_TOTAL) ($MEM_PERCENT%)"

LOAD_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $CPU_COUNT * 0.7}")
if (( $(echo "$LOAD_AVG < $LOAD_THRESHOLD" | bc -l) )); then
    check_pass "System load is acceptable for migration"
else
    check_warn "System load is high - consider waiting"
fi

if [ $MEM_PERCENT -gt 30 ]; then
    check_pass "Sufficient memory available"
else
    check_warn "Low memory available - migration may be slow"
fi

# Summary
print_header "Summary"

TOTAL_CHECKS=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))

echo "Checks performed: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARN_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    if [ $WARN_COUNT -eq 0 ]; then
        echo -e "${GREEN}✓ System is ready for migration${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Review the volumes to be migrated above"
        echo "2. Schedule maintenance window"
        echo "3. Create full backup:"
        echo "   sudo rsync -av /var/lib/rancher/k3s/storage/ /backup/k3s-volumes-\$(date +%Y%m%d)/"
        echo "4. Run dry-run test:"
        echo "   sudo ./scripts/migrate-volumes-to-mnt-storage.sh --dry-run"
        echo "5. Execute migration:"
        echo "   sudo ./scripts/migrate-volumes-to-mnt-storage.sh"
        exit 0
    else
        echo -e "${YELLOW}⚠ System has warnings - review before proceeding${NC}"
        echo ""
        echo "Address warnings above or proceed with caution."
        exit 0
    fi
else
    echo -e "${RED}✗ System is NOT ready for migration${NC}"
    echo ""
    echo "Fix the failed checks above before proceeding."
    exit 1
fi
