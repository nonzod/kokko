# Kokko homelab

```txt
├── base
│   ├── kustomization.yaml
│   ├── coredns
│   │   ├── kustomization.yaml
│   │   └── coredns-config.yaml
│   ├── domotica
│   │   ├── kustomization.yaml
│   │   ├── homeassistant
│   │   │   ├── deployment.yaml
│   │   │   └── service.yaml
│   │   └── esphome
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   └── mdns
│       ├── kustomization.yaml
│       └── deployment.yaml
└── overlays
    ├── development
    │   └── kustomization.yaml
    └── production
        └── kustomization.yaml
```