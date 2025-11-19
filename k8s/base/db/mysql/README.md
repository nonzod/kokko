# MySQL

Versione 8

Necessario abilitare __mysql_native_password__ che è disabilitato

```sh
kubectl create configmap mysql-config --from-file=custom.cnf -n tt-mysql
```