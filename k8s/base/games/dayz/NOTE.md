# Istruzioni Migrazione DayZ Server

## 1. Backup dati esistenti (Raccomandato)

```bash
# Backup configurazione attuale
kubectl get all -n dayz -o yaml > dayz-backup.yaml

# Backup volumi se necessario
sudo rsync -av /mnt/storage/dayz-server-pvc-* /backup/dayz-old/
```

## 2. Rimuovere configurazione esistente

```bash
# Elimina deployment attuale
kubectl delete -k k8s/base/games/dayz/

# Rimuovi i file vecchi
rm -rf k8s/base/games/dayz/
```

## 3. Configurare credenziali Steam

**IMPORTANTE**: Modifica `secrets.yaml` con le tue credenziali Steam reali:

```yaml
stringData:
  STEAM_USERNAME: "tuo_username_steam"
  STEAM_PASSWORD: "tua_password_steam"
  STEAM_GUARD: ""  # Codice Steam Guard se richiesto
```

⚠️ **Nota**: Per installare mod è necessario un account Steam che possiede DayZ.

## 4. Creare nuova struttura file

```bash
# Crea directory per nuova configurazione
mkdir -p k8s/base/games/dayz/

# Salva tutti gli artifact come file YAML nella directory
# - pvc.yaml
# - configmaps.yaml  
# - secrets.yaml (con credenziali configurate)
# - deployment.yaml
# - services.yaml
# - kustomization.yaml
```

## 5. Applicare nuova configurazione

```bash
# Applica la nuova configurazione
kubectl apply -k k8s/base/games/dayz/

# Verifica che i pod si avviino
kubectl get pods -n dayz -w
```

## 6. Gestione server

### Comandi di gestione tramite kubectl:

```bash
# Accesso al container web per gestione
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- bash

# Accesso al container server
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- bash

# Una volta dentro il container, usa gli script dz:
./files/bin/dz status    # Stato server
./files/bin/dz stop      # Ferma server
./files/bin/dz start     # Avvia server
./files/bin/dz install   # Installa/aggiorna server
./files/bin/dz login     # Configura login Steam
```

### Gestione mod:

```bash
# Aggiungi mod (esempio Community Framework)
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- \
  ./files/bin/dz add 1559212036

# Lista mod installate
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- \
  ./files/bin/dz list

# Aggiorna tutti i mod
kubectl exec -it deployment/dayz-server -c dayz-web -n dayz -- \
  ./files/bin/dz modupdate
```

### RCON:

```bash
# Accesso RCON
kubectl exec -it deployment/dayz-server -c dayz-server -n dayz -- \
  ./files/bin/dz rcon
```

## 7. Monitoraggio

```bash
# Log del server
kubectl logs deployment/dayz-server -c dayz-server -n dayz -f

# Log del web container
kubectl logs deployment/dayz-server -c dayz-web -n dayz -f

# Stato generale
kubectl get all -n dayz
```

## 8. Configurazione avanzata

### Modifica configurazione server:
- Edita il ConfigMap `dayz-server-config`
- Applica le modifiche: `kubectl apply -k k8s/base/games/dayz/`
- Riavvia il deployment: `kubectl rollout restart deployment/dayz-server -n dayz`

### Aggiungere spazio storage:
- Edita i PVC per aumentare lo storage
- Applica: `kubectl apply -k k8s/base/games/dayz/`

## Note importanti:

1. **Prima avvio**: Può richiedere molto tempo (download 2.7GB+ file server)
2. **Volumi**: I volumi sono molto più grandi del setup precedente
3. **Credenziali Steam**: Necessarie per mod, opzionali per server vanilla
4. **Gestione**: Tutta la gestione avviene tramite script `dz` integrati
5. **Web interface**: Potrebbere essere disponibile su porta 3000 (da verificare nel progetto originale)

## Troubleshooting:

```bash
# Se container non si avvia
kubectl describe pod -l app=dayz-server -n dayz

# Se problemi con volumi
kubectl get pv,pvc -n dayz

# Reset completo (attenzione: cancella tutti i dati)
kubectl delete namespace dayz
kubectl create namespace dayz
kubectl apply -k k8s/base/games/dayz/
```