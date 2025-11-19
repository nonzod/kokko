# Secrets

## Wireguard

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: wireguard-secrets
  namespace: wireguard
type: Opaque
stringData:
  PASSWORD_HASH: <PASSWORD_HASH>
```

## Pihole

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

## MySQL

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

## Samba

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

## cheshire cat

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cheshire-cat-secrets
  namespace: ai
type: Opaque
stringData:
  OPENAI_API_KEY: "sk-placeholder-key-da-sostituire"
  CCAT_API_KEY: "admin-key-per-proteggere-il-cat"
  QDRANT_API_KEY: "chiave-se-qdrant-è-protetto"
```