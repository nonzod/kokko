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
  namespace: mysql
type: kubernetes.io/basic-auth
stringData:
  password: '<MYSQL_ROOT_PASSWORD>'
```