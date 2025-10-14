#!/bin/bash
set -e

# Controlla se siamo in modalità TEST
if [ "${TEST}" = "true" ]; then
    echo "=== MODALITÀ TEST ATTIVA ==="
    echo "Lo script NON verrà eseguito automaticamente."
    echo "Container pronto per test manuali."
    echo ""
    echo "Per testare i mount, esegui:"
    echo "  kubectl exec -it photo-organizer-pod -n tools -- bash"
    echo ""
    echo "Per eseguire lo script manualmente:"
    echo "  /usr/local/bin/organize_photos.sh -y"
    echo ""
    # Mantieni il container attivo per i test
    tail -f /dev/null
else
    # Lancia lo script di organizzazione foto con conferma automatica
    echo "Avvio dello script di organizzazione foto..."
    /usr/local/bin/organize_photos.sh -y

    # Mantieni il container attivo dopo l'esecuzione
    echo "Script completato. Container in attesa..."
    tail -f /dev/null
fi