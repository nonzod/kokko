Ho preparato la configurazione per il tuo nuovo "Linux Voice Assistant".

Ecco un riepilogo di ciò che ho fatto:

1.  **Dockerfile**: Ho creato un file `build/linux-voice-assistant/Dockerfile` per costruire l'immagine container dell'assistente vocale.
2.  **Manifests Kubernetes**: Ho creato i file necessari per il deployment in `k8s/base/domotica/linux-voice-assistant/`, inclusa la configurazione dei dispositivi audio specifici (`plughw:2,0` per il microfono e `plughw:1,0` per l'uscita).
3.  **Kustomization**: Ho aggiunto il nuovo assistente alla kustomization principale in `k8s/base/domotica/kustomization.yaml`.

**Cosa devi fare ora:**

1.  **Build dell'immagine Docker**: Dovrai costruire l'immagine Docker localmente. Puoi farlo con un comando simile a questo, eseguito dalla root del progetto:
    ```bash
    docker build -t linux-voice-assistant:latest build/linux-voice-assistant
    ```
    Assicurati che il tuo ambiente k3s sia configurato per usare le immagini locali.

2.  **Deployment**: Una volta costruita l'immagine, puoi applicare i manifest con `kubectl apply -k k8s/base/domotica`.

**Note importanti:**

*   **Accesso privilegiato**: Per funzionare, questo container ha bisogno di accesso privilegiato ai dispositivi audio dell'host. L'ho già configurato nel `deployment.yaml`, ma è importante che tu sia consapevole delle implicazioni di sicurezza.
*   **Vecchi deployment**: Come hai notato, i vecchi assistenti vocali (whisper, openwakeword, etc.) non sono inclusi nella kustomization e quindi non verranno deployati.

Fammi sapere se hai bisogno di ulteriore aiuto!
