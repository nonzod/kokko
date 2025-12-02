# K3s Home Infrastructure

Infrastructure repository for K3s-based home services deployment using GitOps with ArgoCD. Configuration management is handled through Kustomize with base configurations and environment-specific overlays.

## Architecture

### Core Components

- **GitOps**: ArgoCD for automated deployment from Git repository
- **Configuration Management**: Kustomize for declarative configuration
- **Ingress**: NGINX Ingress Controller for HTTP/HTTPS routing
- **Certificate Management**: cert-manager with Let's Encrypt
- **Storage**: local-path-provisioner for persistent volumes at `/mnt/storage`
- **DNS**: CoreDNS with custom host entries

### Repository Structure

```
k8s/
├── argocd/
│   └── apps/              # ArgoCD Application definitions
├── base/                  # Base Kubernetes manifests
│   ├── ai/                # AI services (cheshirecat)
│   ├── db/                # Databases (mysql, qdrant)
│   ├── domotica/          # Home automation services
│   ├── http/              # Web services
│   ├── pihole/            # Network ad blocking
│   └── wireguard/         # VPN services
├── certmanager/           # Certificate manager configuration
├── coredns/               # DNS configuration
└── overlays/              # Environment-specific configurations
    ├── development/
    └── production/
```

## Active Services

The following services are currently deployed through Kustomize:

### Domotica Namespace
- **Home Assistant**: Home automation platform
- **ESPHome**: ESP32/ESP8266 device management
- **Samba**: Network file sharing
- **MPD Server**: Music Player Daemon for audio streaming
- **RTSP Server**: Real-Time Streaming Protocol server
- **Wyoming Piper**: Text-to-speech service for Home Assistant

### HTTP Namespace
- **nicolatomassoni**: Personal website

### AI Namespace
- **Cheshire Cat**: AI conversational agent with RAG capabilities

### DB Namespace
- **MySQL**: Relational database
- **Qdrant**: Vector database for AI embeddings

### Other Services
- **Pi-hole**: Network-wide ad blocking (pihole namespace)
- **WireGuard**: VPN server (wireguard namespace)

## Documentation

Detailed documentation is available in the `docs/` directory:

- [STORAGE.md](docs/STORAGE.md) - Persistent storage management, backup and restore procedures
- [SECRETS.md](docs/SECRETS.md) - Secret templates for services requiring credentials
- [ARGOCD.md](docs/ARGOCD.md) - ArgoCD setup and GitOps workflow
- [SERVICES.md](docs/SERVICES.md) - Service-specific configuration and access information
- [GITHUB.md](docs/GITHUB.md) - GitHub Actions runner configuration

## Quick Start

### Prerequisites

- Linux server with minimum 4GB RAM and 2 CPU cores
- K3s installed
- Domain name with DNS configuration
- Port forwarding: 80/443 (HTTP/HTTPS), 51820/UDP (WireGuard)

### Basic Installation

```bash
# Install K3s without Traefik
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -

# Create namespaces
kubectl create namespace domotica
kubectl create namespace http
kubectl create namespace ai
kubectl create namespace db
kubectl create namespace pihole
kubectl create namespace wireguard
```

### Deploy Services

Using Kustomize directly:

```bash
# Deploy all base services
kubectl apply -k k8s/base/domotica/
kubectl apply -k k8s/base/http/
kubectl apply -k k8s/base/ai/
kubectl apply -k k8s/base/db/
kubectl apply -k k8s/base/pihole/
kubectl apply -k k8s/base/wireguard/

# Verify deployment
kubectl get pods --all-namespaces
```

Using ArgoCD (recommended):

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Deploy ArgoCD applications
kubectl apply -f k8s/argocd/apps/
```

See [ARGOCD.md](docs/ARGOCD.md) for detailed GitOps setup.

## Common Operations

### Check Service Status

```bash
# View all pods
kubectl get pods --all-namespaces

# Check specific namespace
kubectl get pods -n domotica

# View logs
kubectl logs -f <pod-name> -n <namespace>
```

### Manage Persistent Storage

```bash
# List persistent volume claims
kubectl get pvc -A

# Check storage usage on host
df -h /mnt/storage/*
```

See [STORAGE.md](docs/STORAGE.md) for backup and restore procedures.

### Certificate Management

```bash
# Check certificate status
kubectl get certificate -A

# View cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

### Update Deployment

```bash
# Apply configuration changes
kubectl apply -k k8s/base/<category>/

# Restart deployment
kubectl rollout restart deployment <deployment-name> -n <namespace>

# Check rollout status
kubectl rollout status deployment <deployment-name> -n <namespace>
```

## Resource Requirements

Minimum resource allocation:
- CPU: 2-4 cores
- RAM: 4-8 GB
- Storage: 50+ GB for persistent volumes

Individual service limits are defined in deployment manifests.

## Security

- Secrets managed through Kubernetes Secret resources
- TLS certificates automated via cert-manager and Let's Encrypt
- VPN access through WireGuard
- Namespace isolation for service separation

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Home Assistant](https://www.home-assistant.io/)
- [Cheshire Cat AI](https://cheshire-cat-ai.github.io/docs/)
