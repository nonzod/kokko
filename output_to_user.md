Ho aggiornato la configurazione per usare la tua immagine su Docker Hub.

Ecco un riepilogo di ciò che ho fatto:

1.  **Dockerfile**: Il file `build/linux-voice-assistant/Dockerfile` è pronto per costruire la tua immagine.
2.  **Manifests Kubernetes**: Ho aggiornato `k8s/base/domotica/linux-voice-assistant/deployment.yaml` per usare l'immagine `nonzod/linux-voice-assistant:latest` da Docker Hub e per usare i dispositivi audio corretti.
3.  **Kustomization**: Il nuovo assistente è aggiunto alla kustomization principale in `k8s/base/domotica/kustomization.yaml`.
4.  **Limiti di Risorse**: Ho aggiunto i limiti di CPU e memoria al deployment.

**Cosa devi fare ora:**

1.  **Build e Push dell'immagine Docker**: Dovrai costruire e pubblicare l'immagine sul tuo account Docker Hub. Puoi farlo con comandi simili a questi, eseguiti dalla root del progetto:
    ```bash
    docker build -t nonzod/linux-voice-assistant:latest build/linux-voice-assistant
    docker push nonzod/linux-voice-assistant:latest
    ```

2.  **Deployment**: Una volta pubblicata l'immagine, puoi applicare i manifest con `kubectl apply -k k8s/base/domotica`.

**Note importanti:**

*   **Accesso privilegiato**: Per funzionare, questo container ha bisogno di accesso privilegiato ai dispositivi audio dell'host. L'ho già configurato nel `deployment.yaml`, ma è importante che tu sia consapevole delle implicazioni di sicurezza.
*   **Vecchi deployment**: I vecchi assistenti vocali non sono inclusi nella kustomization e quindi non verranno deployati.

Fammi sapere se hai bisogno di ulteriore aiuto!
