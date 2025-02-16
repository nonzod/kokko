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
├── base
│   ├── coredns/
│   ├── domotica/
│   │   ├── homeassistant/
│   │   ├── esphome/
│   │   └── pihole/
│   └── mdns/
└── overlays/
    ├── development/
    └── production/
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