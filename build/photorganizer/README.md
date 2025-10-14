kubectl create secret generic ssh-key-secret \
  --from-file=id_rsa.pub=./k3s_organizer_key.pub \
  -n tools

docker build -t nonzod/photo-organizer:latest .

docker push nonzod/photo-organizer:latest

kubectl apply -f organizer-pod.yaml

kubectl get pod,pvc,pv,svc

Connettiti via SSH:

IP del Nodo: Trova l'indirizzo IP di uno dei tuoi nodi k3s.

Porta: Usa la nodePort definita nel servizio (nel nostro caso 30022).

Chiave: Usa la chiave privata che hai generato (k3s_organizer_key).

Bash

ssh -i ./k3s_organizer_key -p 30022 organizer@kubensis.local



# Per organizzare la libreria "in-place"
/usr/local/bin/organize_photos.sh

# Per importare file dalla cartella di importazione
# 1. Imposta la destinazione nello script (è già /mnt/photos_destination se lo modifichi)
# 2. Lancia l'importazione
/usr/local/bin/organize_photos.sh /mnt/photos_source