# Home Assistant K8s Configuration

Kubernetes configuration for Home Assistant and related services using Kustomize.

## Services

- **Home Assistant**: Home automation platform
- **ESPHome**: ESP32/ESP8266 devices management
- **Pi-hole**: Network-wide ad blocking
- **CoreDNS**: DNS server configuration
- **mDNS**: Multicast DNS for service discovery

## Structure

```
.
├── argocd
│   ├── configMap.yml
│   ├── ingress.yml
│   └── README.md
├── base
│   ├── backrest
│   │   ├── configmap.yaml
│   │   ├── deployment.yml
│   │   ├── kustomization.yaml
│   │   ├── pvc.yaml
│   │   └── service.yaml
│   ├── domotica
│   │   ├── esphome
│   │   │   ├── deployment.yaml
│   │   │   ├── ingress.yaml
│   │   │   ├── kustomization.yaml
│   │   │   ├── pvc.yaml
│   │   │   └── service.yaml
│   │   ├── homeassistant
│   │   │   ├── deployment.yaml
│   │   │   ├── ingress.yaml
│   │   │   ├── kustomization.yaml
│   │   │   ├── pvc.yaml
│   │   │   └── service.yaml
│   │   └── kustomization.yaml
│   ├── http
│   │   ├── kustomization.yaml
│   │   ├── nicolatomassoni
│   │   │   ├── deployment.yaml
│   │   │   ├── ingress.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── service.yaml
│   │   └── scmapping
│   │       ├── deployment.yaml
│   │       ├── ingress.yaml
│   │       ├── kustomization.yaml
│   │       └── service.yaml
│   ├── kustomization.yaml
│   ├── pihole
│   │   ├── deployment.yaml
│   │   ├── ingress.yaml
│   │   ├── kustomization.yaml
│   │   ├── pvc.yaml
│   │   ├── secret.yaml
│   │   └── service.yaml
│   └── wireguard
│       ├── configmap.yaml
│       ├── deployment.yaml
│       ├── kustomization.yaml
│       ├── pvc.yaml
│       ├── secret.yaml
│       └── service.yaml
├── certmanager
│   ├── cluster-issuer.yaml
│   └── README.md
├── coredns
│   ├── coredns-config.yaml
│   └── kustomization.yaml
├── local-path-config.yaml
└── overlays
    ├── development
    │   └── kustomization.yaml
    └── production
        └── kustomization.yaml
```

## Prerequisites

- Kubernetes cluster
- kubectl
- kustomize

## Deployment

1. Create required namespace:
```bash
kubectl create namespace domotica
```

2. Update configurations:
   - Set Pi-hole password in `base/domotica/pihole/secret.yaml`
   - Adjust IP addresses and resources as needed

3. Apply configuration:
```bash
kubectl apply -k base/
```

## Services Access

- **Home Assistant**: `http://<host-ip>:8123`
- **Pi-hole**: `http://<host-ip>:8000`
- **ESPHome**: `http://<host-ip>:6052` (direct host network access)

## Storage

All persistent data is stored in `/mnt/ha-config/`:
- `/mnt/ha-config/` - Home Assistant
- `/mnt/ha-config/esphome/` - ESPHome
- `/mnt/ha-config/pihole/` - Pi-hole

## Notes

- ESPHome uses host network for device discovery
- Pi-hole serves DNS (53) and DHCP (67) on host network
- All configurations use resource limits to ensure stable operation