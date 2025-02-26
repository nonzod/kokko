# Kubernetes Home Infrastructure

This repository contains the Kubernetes configuration for a home infrastructure setup using K3s, Kustomize, and ArgoCD for GitOps. The setup includes various services like Home Assistant, ESPHome, Pi-hole, WireGuard VPN, and web services.

## Architecture Overview

The infrastructure is built on K3s with the following components:

- **GitOps**: ArgoCD for continuous deployment from Git
- **Service Discovery**: CoreDNS with custom host entries
- **Certificate Management**: cert-manager with Let's Encrypt
- **Ingress**: NGINX Ingress Controller
- **Storage**: Local-path-provisioner for persistent storage
- **Namespaces**:
  - `domotica`: Home automation services
  - `http`: Web services
  - `pihole`: Network-wide ad blocking
  - `wireguard`: VPN services
  - `restic`: Backups
  - `argocd`: GitOps deployment
  - `cert-manager`: Certificate management

## Services

| Service | Description | Access |
|---------|-------------|--------|
| **Home Assistant** | Home automation platform | `https://my.domain.tld/` |
| **ESPHome** | ESP32/ESP8266 management | `https://my.domain.tld/esphome/` |
| **Pi-hole** | Network-wide ad blocking | `https://my.domain.tld/pihole/` |
| **WireGuard** | VPN server with Web UI | `https://<server-ip>:51821/` |
| **Personal Website** | Static website | `https://my.domain.tld/` |
| **SC Mapping** | Custom NodeJS application | `https://second.domain.tld/` |
| **ArgoCD** | GitOps UI | `https://argocd.my.domain.tld/` |
| **Backrest** | Restic backup UI | `http://<server-ip>:9898/` |

## Directory Structure

```
k8s/
├── argocd/               # ArgoCD configuration
├── base/                 # Base configurations
│   ├── backrest/         # Backup management
│   ├── domotica/         # Home automation
│   │   ├── esphome/      # ESP device management
│   │   └── homeassistant/# Home Assistant
│   ├── http/             # Web services
│   │   ├── nicolatomassoni/ # Personal website
│   │   └── scmapping/    # SC Mapping application
│   ├── pihole/           # Network ad blocking
│   └── wireguard/        # VPN server
├── certmanager/          # Certificate management
├── coredns/              # DNS configuration
└── overlays/             # Environment-specific overlays
    ├── development/      # Development environment
    └── production/       # Production environment
```

## Prerequisites

- Linux server with at least 4GB RAM and 2 CPU cores
- K3s installed
- Domain name(s) with proper DNS configuration
- Port forwarding for:
  - 80/443 (HTTP/HTTPS)
  - 51820/UDP (WireGuard)
  - 51821/TCP (WireGuard Web UI)

## Installation Guide

### 1. Install K3s

```bash
curl -sfL https://get.k3s.io | sh -
```

For a minimal installation without Traefik (since we'll use NGINX Ingress):

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```

### 2. Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

### 3. Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.0 \
  --set installCRDs=true
```

Apply the ClusterIssuer configuration:

```bash
kubectl apply -f k8s/certmanager/cluster-issuer.yaml
```

### 4. Create Required Namespaces

```bash
kubectl create namespace domotica
kubectl create namespace http
kubectl create namespace pihole
kubectl create namespace wireguard
kubectl create namespace restic
```

### 5. Create Secrets

Create the required secrets (see SECRETS.md for templates):

```bash
# For WireGuard
kubectl apply -f wireguard-secrets.yaml

# For Pi-hole
kubectl apply -f pihole-secret.yaml
```

### 6. Apply Storage Configuration

```bash
kubectl apply -f k8s/local-path-config.yaml
```

### 7. Install ArgoCD (Optional, for GitOps)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f k8s/argocd/configmap.yml
kubectl apply -f k8s/argocd/ingress.yml

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 8. Deploy the Services

Using kubectl and kustomize:

```bash
# Deploy all services
kubectl apply -k k8s/base/

# Or deploy individual services
kubectl apply -k k8s/base/domotica/
kubectl apply -k k8s/base/http/
kubectl apply -k k8s/base/pihole/
kubectl apply -k k8s/base/wireguard/
```

Or using ArgoCD:

1. Create an application in ArgoCD pointing to your Git repository
2. Set the path to `k8s/base`
3. Set the destination to your cluster
4. Enable auto-sync

## Service Configuration

### Home Assistant and ESPHome

The configuration files are stored in persistent volumes:
- Home Assistant: `/mnt/storage/ha-config-pvc`
- ESPHome: `/mnt/storage/esphome-config-pvc`

### Pi-hole

The Pi-hole configuration files are stored in:
- `/mnt/storage/pihole-etc-pvc`
- `/mnt/storage/dnsmasq-etc-pvc`

### WireGuard

The WireGuard configuration files are stored in:
- `/mnt/storage/wireguard-data-pvc`

### CoreDNS

To add local DNS entries, edit the ConfigMap:

```bash
kubectl edit configmap coredns -n kube-system
```

Or apply the configuration from the repository:

```bash
kubectl apply -k k8s/coredns/
```

## Environment-Specific Configurations

The repository includes overlay directories for development and production environments:

```bash
# For development
kubectl apply -k k8s/overlays/development/

# For production
kubectl apply -k k8s/overlays/production/
```

## Accessing Services

### Local Network

Services with LoadBalancer type (Home Assistant, ESPHome, Pi-hole, WireGuard) can be accessed directly via the node IP:

- Home Assistant: `http://<node-ip>:8123`
- ESPHome: `http://<node-ip>:6052`
- Pi-hole: `http://<node-ip>:8000`
- WireGuard Web UI: `http://<node-ip>:51821`

### External Access (via Ingress)

All services configured with Ingress can be accessed via their respective domain names:

- Home Assistant: `https://my.domain.tld/`
- ESPHome: `https://my.domain.tld/esphome/`
- Pi-hole: `https://my.domain.tld/pihole/`
- Personal Website: `https://my.domain.tld/` and `https://www.my.domain.tld/`
- SC Mapping: `https://second.domain.tld/`
- ArgoCD: `https://argocd.my.domain.tld/`

## Monitoring and Troubleshooting

### Check Ingress Status

```bash
kubectl get ingress --all-namespaces
kubectl describe ingress <ingress-name> -n <namespace>
```

### Check Certificates

```bash
kubectl get certificate --all-namespaces
kubectl describe certificate <cert-name> -n <namespace>
```

### Check Running Pods

```bash
kubectl get pods --all-namespaces
kubectl describe pod <pod-name> -n <namespace>
```

### View Logs

```bash
kubectl logs <pod-name> -n <namespace>
```

## Backup and Restore

For backup management, the setup includes Backrest, a web UI for Restic backups.

```bash
kubectl apply -k k8s/base/backrest/
```

Access the Backrest UI at `http://<node-ip>:9898`

## Security Considerations

- Credentials are stored in Kubernetes secrets
- HTTPS is enforced via cert-manager and Let's Encrypt
- WireGuard provides secure remote access to the network
- Resources are isolated using namespaces

## Resource Requirements

The entire setup requires approximately:
- 2-4 CPU cores
- 4-8 GB RAM
- 50+ GB storage space

Individual service requirements are defined in the deployment manifests with resource limits.

## References

- K3s: https://k3s.io/
- ArgoCD: https://argo-cd.readthedocs.io/
- Kustomize: https://kustomize.io/
- Home Assistant: https://www.home-assistant.io/
- ESPHome: https://esphome.io/
- Pi-hole: https://pi-hole.net/
- WireGuard: https://www.wireguard.com/
- Cert-Manager: https://cert-manager.io/