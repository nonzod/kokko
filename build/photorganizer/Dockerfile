# Usa un'immagine di base leggera ma stabile
FROM debian:bullseye-slim

# Installa tutte le dipendenze necessarie in un unico passaggio
RUN apt-get update && apt-get install -y --no-install-recommends \
    jdupes \
    libimage-exiftool-perl \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Copia il tuo script di organizzazione nell'immagine
COPY organize_nas_photo-5.1.sh /usr/local/bin/organize_photos.sh
RUN chmod +x /usr/local/bin/organize_photos.sh

# Script di avvio
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Esegui l'entrypoint all'avvio del container
ENTRYPOINT ["/entrypoint.sh"]