# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a K3s home infrastructure repository for deploying and managing personal services using GitOps with ArgoCD. The infrastructure uses Kustomize for configuration management and is organized into base configurations and environment-specific overlays.

## Architecture

### Repository Structure

- **k8s/base/**: Base Kubernetes manifests organized by service category
  - `domotica/`: Home automation services (Home Assistant, ESPHome, Samba, MPD server, voice pipeline)
  - `http/`: Web services (personal websites, custom applications)
  - `ai/`: AI services (n8n, Ollama, Cheshire Cat)
  - `db/`: Database services (MySQL, PostgreSQL, Qdrant)
  - `games/`: Game servers (DayZ)
  - `pihole/`: Network ad blocking
  - `wireguard/`: VPN services

- **k8s/overlays/**: Environment-specific configurations
  - `development/`: Development environment overrides
  - `production/`: Production environment configurations

- **k8s/argocd/apps/**: ArgoCD Application manifests that reference base configurations
  - Each Application points to a path in `k8s/base/` and syncs to the cluster

- **build/**: Custom Docker builds (GStreamer, photo organizer)
- **docs/**: Documentation (STORAGE.md for persistent volume management)

### Key Technologies

- **K3s**: Lightweight Kubernetes distribution
- **ArgoCD**: GitOps deployment with automated sync policies (prune: true, selfHeal: true)
- **Kustomize**: Configuration management via kustomization.yaml files
- **cert-manager**: TLS certificate management with Let's Encrypt
- **NGINX Ingress**: HTTP/HTTPS routing and external access
- **local-path-provisioner**: Persistent storage at `/mnt/storage` on host

### Storage Management

All persistent volumes are stored on the host at `/mnt/storage/` using local-path-provisioner. Each PVC creates a subdirectory with a unique suffix (e.g., `/mnt/storage/ha-config-pvc-xxx/`). See [docs/STORAGE.md](docs/STORAGE.md) for backup, restore, and troubleshooting procedures.

## Common Commands

### Deployment and Updates

```bash
# Apply base configurations with Kustomize
kubectl apply -k k8s/base/domotica/
kubectl apply -k k8s/base/http/
kubectl apply -k k8s/base/ai/

# Apply environment-specific overlays
kubectl apply -k k8s/overlays/production/
kubectl apply -k k8s/overlays/development/

# Verify kustomization without applying
kubectl kustomize k8s/base/domotica/
```

### ArgoCD Management

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Verify webhook configuration
kubectl get configmap argocd-cm -n argocd -o yaml

# Restart ArgoCD server after configuration changes
kubectl rollout restart deployment argocd-server -n argocd
```

### Service Monitoring

```bash
# Check all pods across namespaces
kubectl get pods --all-namespaces

# Check specific service
kubectl get pods -n domotica
kubectl describe pod <pod-name> -n domotica

# View logs
kubectl logs <pod-name> -n <namespace>
kubectl logs -f <pod-name> -n <namespace>  # Follow logs
```

### Certificate Management

```bash
# Verify ingress configuration
kubectl describe ingress <ingress-name> -n <namespace>

# Check certificate status
kubectl get certificate -n <namespace>
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

### Storage Operations

```bash
# Check PVC status
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <namespace>

# Check PV status
kubectl get pv

# Restart deployment after volume changes
kubectl rollout restart deployment <deployment-name> -n <namespace>
```

## Working with Manifests

### Adding a New Service

1. Create service directory under `k8s/base/<category>/<service-name>/`
2. Add required manifests: deployment.yaml, service.yaml, pvc.yaml (if needed), ingress.yaml (for external access)
3. Create kustomization.yaml listing all resources
4. Add service to parent kustomization.yaml in `k8s/base/<category>/kustomization.yaml`
5. Create ArgoCD Application in `k8s/argocd/apps/<category>.yaml` or add to existing

### Deployment Conventions

- Set `imagePullPolicy: Always` for deployments that should pull latest images
- Use resource limits and requests for all containers
- Include liveness and readiness probes for HTTP services
- Use namespace-specific kustomization files to set default namespace
- DNS configuration often includes `ndots: "1"` for performance

### ArgoCD Applications

All ArgoCD Applications use:
- `repoURL: git@github.com:nonzod/kokko.git`
- `targetRevision: HEAD`
- `automated.prune: true` - removes resources deleted from Git
- `automated.selfHeal: true` - reverts manual changes to match Git

## WireGuard VPN Configuration

### Home Assistant WireGuard Client

Home Assistant uses a WireGuard sidecar container to reach remote networks (e.g., 10.0.5.0/24) via VPN while maintaining normal cluster connectivity.

**Architecture:**
- Sidecar container `wireguard-client` runs alongside Home Assistant in the same pod
- Both containers share the same network namespace
- Only traffic to specified subnets (AllowedIPs) routes through the VPN tunnel
- All other traffic (including cluster DNS and services) uses normal routing

**Configuration:**
1. Create the WireGuard secret manually (not in git):
   ```bash
   kubectl apply -f secret.yaml -n domotica
   ```

2. Secret structure (`homeassistant-wireguard-client`):
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: homeassistant-wireguard-client
     namespace: domotica
   type: Opaque
   stringData:
     wg0.conf: |
       [Interface]
       PrivateKey = <client_private_key>
       Address = 10.8.0.5/24
       # DO NOT set DNS here - it breaks cluster DNS resolution!

       [Peer]
       PublicKey = <server_public_key>
       PresharedKey = <optional_preshared_key>
       Endpoint = <server_ip>:51820
       AllowedIPs = 10.0.5.0/24
       PersistentKeepalive = 25
   ```

**Important:**
- Never set `DNS` in the WireGuard config - it overrides cluster DNS and breaks service discovery
- Only the subnet in `AllowedIPs` routes through VPN; cluster traffic remains unaffected
- The secret is excluded from git and must be applied manually

**Troubleshooting:**
```bash
# Check tunnel status
kubectl exec -n domotica deployment/homeassistant -c wireguard-client -- wg show

# Test VPN connectivity
kubectl exec -n domotica deployment/homeassistant -c homeassistant -- ping 10.0.5.1

# Verify DNS resolution (should use cluster DNS, not 1.1.1.1)
kubectl exec -n domotica deployment/homeassistant -c homeassistant -- nslookup stt-openwakeword
```

## Important Notes

- The repository uses private GitHub repository: `git@github.com:nonzod/kokko.git`
- Secrets are excluded from version control (see .gitignore) and must be managed separately
- All services in the `domotica` namespace are related to home automation
- Storage paths on host are at `/mnt/storage/` - never use other paths without updating local-path-config
- When modifying deployments, consider whether ArgoCD will auto-sync the changes or if manual intervention is needed
