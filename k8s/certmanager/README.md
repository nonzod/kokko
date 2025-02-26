# Cert manager

[Riferimento](https://hbayraktar.medium.com/installing-cert-manager-and-nginx-ingress-with-lets-encrypt-on-kubernetes-fe0dff4b1924)

```sh
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
--namespace cert-manager --create-namespace \
--version v1.12.0 \
--set installCRDs=true
```

Verifica Ingress

`kubectl describe ingress <ingress> -n <namespace>`

Verifica ci sia il certificato

`kubectl get certificate -n <namespace>`

Dettagli certificato

`kubectl describe certificate <issuer> -n <namespace>`

Log del cert manager

`kubectl describe certificate <issuer> -n <namespace>`