# Guida Migrazione DayZ Multi-Container

## Panoramica

Questa configurazione replica **esattamente** il setup docker-compose originale con:

- **Container Web** (`debian:bookworm-slim`): SteamCMD, gestione mod, web UI
- **Container Server** (`debian:bookworm-slim`): solo server DayZ
- **Volumi condivisi**: identici al docker-compose originale
- **Network**: host mode per LAN detection (come nell'originale)

## Struttura File

Salva tutti gli artifact come file YAML nella directory `k8s/base/games/dayz/`:

```
k8s/base/games/dayz/
├── namespace.yaml          # Namespace dayz
├── pvc.yaml               # PVC per i volumi persistenti
├── configmaps.yaml        # Configurazione server
├── secrets.yaml           # Credenziali Steam
├── deployment.yaml        # Multi-container deployment
├── services.yaml          # Servizi per web UI
└── kustomization.yaml     # Orchestrazione Kustomize
```

## 1. Backup Configurazione Attuale

```bash
# Backup completo
kubectl get all -n dayz -o yaml > dayz-backup-$(date +%Y%m%d).yaml

# Backup dati (opzionale se importanti)
kubectl get pvc -n dayz
```

## 2. Rimuovere Setup Precedente

```bash
# Elimina deployment attuale
kubectl delete -k k8s/base/games/dayz/ 2>/dev/null || true

# Elimina namespace (attenzione: cancella TUTTI i dati)
kubectl delete namespace dayz 2>/dev/null || true
```

## 3. Configurare Credenziali Steam

**IMPORTANTE**: Modifica `secrets.yaml` prima di applicare:

```yaml
stringData:
  STEAM_USERNAME: "tuo_username_steam"  # OBBLIGATORIO per mod
  STEAM_PASSWORD: "tua_password_steam"  
  STEAM_GUARD: ""  # Se necessario
```

⚠️ **Nota**: Per installare mod è **necessario** un account Steam che possiede DayZ.

## 4. Applicare Nuova Configurazione

```bash
# Applica tutto il setup
kubectl apply -k k8s/base/games/dayz/

# Verifica deployment
kubectl get pods -n dayz -w
```

## 5. Primo Avvio e Setup

### Verifica Container

```bash
# Stato generale
kubectl get all -n dayz

# Log dei container
kubectl logs -f deployment/dayz-server -c dayz-web -n dayz     # Web container
kubectl logs -f deployment/dayz-server -c dayz-server -n dayz  # Server container
```

### Login Steam (nel container web)

```bash
# Accesso al container web
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- bash

# Login Steam (necessario per mod)
dz login
# Segui le istruzioni, inserisci credenziali, approva Steam Guard
```

### Installazione Server (nel container web)

```bash
# Dal container web, installa server files
dz install
# Download ~3GB di file
```

### Configurazione Server (nel container server)

```bash
# Accesso al container server  
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- bash

# Applica configurazione
dz config
```

## 6. Gestione Operativa

### Comandi Web Container (gestione mod e aggiornamenti)

```bash
# Accesso container web
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- bash

# Gestione mod
dz add 1559212036        # Aggiungi mod (Community Framework)
dz list                  # Lista mod installate
dz modupdate            # Aggiorna tutti i mod
dz remove 1559212036    # Rimuovi mod

# Aggiornamenti
dz update               # Aggiorna server files
```

### Comandi Server Container (gestione server)

```bash
# Accesso container server
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- bash

# Gestione server
dz status               # Stato server
dz stop                 # Ferma server
dz start                # Avvia server  
dz restart              # Riavvia server
dz force                # Kill forzato (emergenza)

# Gestione mod (nel server)
dz activate 1559212036  # Attiva mod installata
dz deactivate 1559212036 # Disattiva mod
dz list                 # Lista mod attive
```

### RCON

```bash
# Dal container server
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- dz rcon
```

## 7. Accesso Servizi

### Web UI
- **Web UI**: `http://<node-ip>:30800`
- **Web API**: `http://<node-ip>:30801`

### Server DayZ (hostNetwork)
- **Game Port**: `<node-ip>:2302/UDP`
- **RCON Port**: `<node-ip>:2303/UDP`  
- **Steam Port**: `<node-ip>:27016/UDP`

## 8. Monitoraggio

```bash
# Log in tempo reale
kubectl logs -f deployment/dayz-server -c dayz-web -n dayz
kubectl logs -f deployment/dayz-server -c dayz-server -n dayz

# Stato risorse
kubectl top pods -n dayz
kubectl get pvc -n dayz

# Eventi
kubectl get events -n dayz --sort-by='.lastTimestamp'
```

## 9. Troubleshooting

### Container non si avvia

```bash
# Descrizione pod
kubectl describe pod -l app=dayz-server -n dayz

# Log init container
kubectl logs -f dayz-server-xxx -c setup-files -n dayz
```

### Problemi permessi volumi

```bash
# Fix permessi (se necessario)
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- \
  bash -c "sudo chown -R 1000:1000 /serverfiles /mods /home/user"
```

### Server non si avvia

```bash
# Verifica file installazione
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- \
  ls -la /serverfiles/DayZServer

# Verifica configurazione
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- \
  dz status
```

### Reset completo

```bash
# Attenzione: cancella TUTTI i dati
kubectl delete namespace dayz
kubectl apply -k k8s/base/games/dayz/
```

## Differenze Principali vs Docker-Compose

✅ **Identico al docker-compose**:
- Due container separati (web + server)
- Stesse immagini base (`debian:bookworm-slim`)
- Stessi volumi e mount point
- Stesso PATH e environment
- Host networking per LAN detection
- Script `dz` funzionali in entrambi i container

✅ **Miglioramenti K3s**:
- Health checks automatici
- Restart policy gestiti da K3s
- Resource limits definiti
- Storage persistente garantito
- Monitoring integrato

⚠️ **Note**:
- Il primo avvio richiede setup manuale (login Steam + installazione)
- Le credenziali Steam devono essere configurate nei secrets
- Volumi più grandi per accommodare mod e server files
- Network hostNetwork per mantenere compatibilità LAN