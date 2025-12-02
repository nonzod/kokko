# Services Configuration and Access

This document provides detailed information about each service deployed in the cluster, including configuration requirements, access methods, and troubleshooting.

## Domotica Namespace

### Home Assistant

Home automation platform for controlling smart home devices and automation.

**Configuration:**
- Persistent storage: `/mnt/storage/ha-config-pvc-*` (12Gi)
- ConfigMap: Additional configuration via `homeassistant-config`
- Resource limits: 2Gi memory, 1 CPU core

**Access:**
- External (HTTPS): `https://casa.nicolatomassoni.it`
- Internal (LoadBalancer): `http://192.168.178.43:8123`
- Service port: 8123

**Manifest location:** `k8s/base/domotica/homeassistant/`

**Troubleshooting:**
```bash
# Check pod status
kubectl get pods -n domotica -l app=homeassistant

# View logs
kubectl logs -f -n domotica deployment/homeassistant

# Restart service
kubectl rollout restart deployment homeassistant -n domotica
```

### ESPHome

Management platform for ESP32/ESP8266 devices with over-the-air updates.

**Configuration:**
- Persistent storage: `/mnt/storage/esphome-config-pvc-*` (4Gi)
- Resource limits: 1Gi memory, 500m CPU

**Access:**
- External (HTTPS): `https://esphome.nicolatomassoni.it`
- Internal (LoadBalancer): `http://192.168.178.43:6052`
- Service port: 6052

**Manifest location:** `k8s/base/domotica/esphome/`

### Samba Server

Network file sharing for Home Assistant configuration access.

**Configuration:**
- Mounts Home Assistant PVC as read-write
- Secret required: `samba-credentials` with password
- Resource limits: 256Mi memory, 200m CPU

**Access:**
- LoadBalancer: `smb://192.168.178.43:445`
- NetBIOS port: 139

**Secret template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: samba-credentials
  namespace: domotica
type: Opaque
stringData:
  password: <SAMBA_PASSWORD>
```

**Manifest location:** `k8s/base/domotica/samba/`

### MPD Server

Music Player Daemon for audio streaming to multiple clients.

**Configuration:**
- Persistent storage for music library and playlists
- Requires music files to be present in volume
- Resource limits: 512Mi memory, 500m CPU

**Access:**
- MPD protocol: Port 6600
- HTTP streaming: Port 8000

**Manifest location:** `k8s/base/domotica/mpd-server/`

### RTSP Server

Real-Time Streaming Protocol server for video streaming.

**Configuration:**
- Resource limits: 512Mi memory, 500m CPU
- Supports multiple concurrent streams

**Access:**
- RTSP protocol: Port 8554

**Manifest location:** `k8s/base/domotica/rtsp-server/`

### Wyoming Piper

Text-to-speech service for Home Assistant voice integration.

**Configuration:**
- Image: `rhasspy/wyoming-piper:latest`
- Resource limits: 1Gi memory, 500m CPU
- Pre-loaded voice models

**Access:**
- Internal service: Port 10200
- Used by Home Assistant for TTS

**Manifest location:** `k8s/base/domotica/wyoming-piper/`

## HTTP Namespace

### nicolatomassoni (Personal Website)

Static website served via NGINX.

**Configuration:**
- Resource limits: 128Mi memory, 100m CPU
- Static content in container image

**Access:**
- External (HTTPS): `https://nicolatomassoni.it` and `https://www.nicolatomassoni.it`
- Service port: 80

**Manifest location:** `k8s/base/http/nicolatomassoni/`

**Update deployment:**
```bash
# Rebuild and push container image
# Update deployment to pull new image
kubectl rollout restart deployment nicolatomassoni -n http
```

## AI Namespace

### Cheshire Cat

AI conversational agent with Retrieval-Augmented Generation (RAG) capabilities.

**Configuration:**
- Persistent storage:
  - `/app/cat/data` - Vector embeddings and conversation history
  - `/app/cat/plugins` - Custom plugins
  - `/app/cat/static` - Static assets
- Secret required: `cheshire-cat-secrets` with API keys
- Resource limits: 4Gi memory, 2 CPU cores
- Depends on Qdrant vector database

**Access:**
- External (HTTPS): `https://cat.nicolatomassoni.it`
- Service port: 80
- API documentation: `https://cat.nicolatomassoni.it/docs`

**Secret template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cheshire-cat-secrets
  namespace: ai
type: Opaque
stringData:
  OPENAI_API_KEY: "sk-your-openai-key"
  CCAT_API_KEY: "your-admin-api-key"
  QDRANT_API_KEY: "qdrant-api-key-if-protected"
```

**Manifest location:** `k8s/base/ai/cheshirecat/`

**Troubleshooting:**
```bash
# Check pod status
kubectl get pods -n ai -l app=cheshire-cat

# View logs
kubectl logs -f -n ai deployment/cheshire-cat-core

# Check Qdrant connection
kubectl logs -n ai deployment/cheshire-cat-core | grep -i qdrant
```

## DB Namespace

### MySQL

Relational database for applications requiring structured data storage.

**Configuration:**
- Persistent storage: `/mnt/storage/mysql-data-pvc-*`
- Secret required: `mysql-secret` with root password
- Resource limits: 2Gi memory, 1 CPU core

**Access:**
- External (LoadBalancer): `192.168.178.43:3306`
- Internal service: `mysql.db.svc.cluster.local:3306`

**Secret template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: db
type: kubernetes.io/basic-auth
stringData:
  password: '<MYSQL_ROOT_PASSWORD>'
```

**Manifest location:** `k8s/base/db/mysql/`

**Connection example:**
```bash
# From within cluster
mysql -h mysql.db.svc.cluster.local -u root -p

# From host network
mysql -h 192.168.178.43 -u root -p
```

### Qdrant

Vector database for AI embeddings and similarity search.

**Configuration:**
- StatefulSet with persistent volume
- Storage: 10Gi for vector data
- Resource limits: 2Gi memory, 1 CPU core
- Telemetry disabled for K8s deployment

**Access:**
- HTTP API: Port 6333
- gRPC API: Port 6334
- Internal service: `qdrant.db.svc.cluster.local:6333`
- Health check: `http://qdrant.db.svc.cluster.local:6333/healthz`

**Manifest location:** `k8s/base/db/qdrant/`

**Usage:**
```bash
# Check Qdrant health
kubectl exec -it -n ai deployment/cheshire-cat-core -- \
  curl http://qdrant.db.svc.cluster.local:6333/healthz

# View collections
kubectl exec -it -n ai deployment/cheshire-cat-core -- \
  curl http://qdrant.db.svc.cluster.local:6333/collections
```

## Pihole Namespace

### Pi-hole

Network-wide ad blocking and DNS management.

**Configuration:**
- Persistent storage:
  - `/mnt/storage/pihole-etc-pvc-*` (1Gi) - Pi-hole configuration
  - `/mnt/storage/dnsmasq-etc-pvc-*` (8Gi) - DNS configuration
- Secret required: `pihole-secret` with web password
- Resource limits: 512Mi memory, 500m CPU

**Access:**
- External (HTTPS): `https://pihole.nicolatomassoni.it`
- Internal (LoadBalancer): `http://192.168.178.43:8000`
- DNS service: `192.168.178.43:53` (TCP/UDP)
- Admin interface: Web UI at `/admin`

**Secret template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pihole-secret
  namespace: pihole
type: Opaque
stringData:
  webpassword: <PASSWORD>
```

**Manifest location:** `k8s/base/pihole/`

**Configuration:**
```bash
# Access admin interface
# Login with password from pihole-secret

# Configure as DNS server for clients
# Set DNS to 192.168.178.43 in DHCP or client network settings
```

## Wireguard Namespace

### WireGuard VPN

VPN server with web-based client management interface.

**Configuration:**
- Persistent storage: `/mnt/storage/wireguard-data-pvc-*` (4Gi)
- Secret required: `wireguard-secrets` with web UI password hash
- Resource limits: 512Mi memory, 500m CPU

**Access:**
- VPN endpoint: `192.168.178.43:51820` (UDP)
- Web UI (LoadBalancer): `http://192.168.178.43:51821`

**Secret template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: wireguard-secrets
  namespace: wireguard
type: Opaque
stringData:
  PASSWORD_HASH: <BCRYPT_PASSWORD_HASH>
```

**Generate password hash:**
```bash
# Install bcrypt tool
pip install bcrypt

# Generate hash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'your-password', bcrypt.gensalt()).decode())"
```

**Manifest location:** `k8s/base/wireguard/`

**Client setup:**
1. Access web UI at `http://192.168.178.43:51821`
2. Create new client configuration
3. Download WireGuard configuration file
4. Import into WireGuard client application

## Certificate Management

All HTTPS-enabled services use Let's Encrypt certificates managed by cert-manager.

**ClusterIssuer:** `letsencrypt-office`

**Check certificate status:**
```bash
# List all certificates
kubectl get certificate -A

# Check specific certificate
kubectl describe certificate <cert-name> -n <namespace>

# View cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

**Certificate renewal:**
Certificates are automatically renewed by cert-manager 30 days before expiration.

## Persistent Storage

All services with persistent storage use local-path provisioner with volumes stored at `/mnt/storage` on the host.

See [STORAGE.md](STORAGE.md) for detailed storage management procedures.

## Adding New Services

To add a new service to the cluster:

1. Create service directory structure:
```bash
mkdir -p k8s/base/<category>/<service-name>
cd k8s/base/<category>/<service-name>
```

2. Create manifest files:
- `deployment.yaml` or `statefulset.yaml`
- `service.yaml`
- `pvc.yaml` (if persistent storage needed)
- `ingress.yaml` (if external HTTPS access needed)
- `configmap.yaml` (if configuration needed)
- `kustomization.yaml` (list all resources)

3. Update parent kustomization:
```bash
# Edit k8s/base/<category>/kustomization.yaml
# Add service to resources list
```

4. Create ArgoCD Application (optional):
```bash
# Create or update k8s/argocd/apps/<category>.yaml
```

5. Apply configuration:
```bash
kubectl apply -k k8s/base/<category>/
# or commit to Git for ArgoCD sync
```

See [ARGOCD.md](ARGOCD.md) for GitOps deployment workflow.
