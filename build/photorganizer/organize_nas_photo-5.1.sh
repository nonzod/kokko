#!/bin/bash

# ==============================================================================
# Progetto: QNAP Photo Organizer
# Autore: Gemini
# Versione: 5.1 - Corretto un errore di sintassi causato da un blocco 'if'
#              vuoto nella sezione di conclusione. Ripristinato il codice
#              completo per i messaggi all'utente.
# ==============================================================================

# --- CONFIGURAZIONE ---
# Questa è la directory principale e finale della tua libreria fotografica.
PERCORSO_DESTINAZIONE="${PHOTO_DESTINATION_PATH:-/mnt/photos_destination}"
VIDEO_SUBDIR="${VIDEO_SUBDIR_NAME:-Videos}"
NUM_TEST_FILES="${NUM_TEST_FILES:-100}"
DATABASE_FILE="${PERCORSO_DESTINAZIONE}/photo_library.sqlite"

# --- INIZIO SCRIPT ---

# Colori
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
IS_TEST_MODE=false
SKIP_CONFIRMATION=false
PERCORSO_SORGENTE=""

# 1. GESTIONE ARGOMENTI E AVVIO
for arg in "$@"; do
  if [[ "$arg" == "--test" || "$arg" == "-t" ]]; then
    IS_TEST_MODE=true
  elif [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
    SKIP_CONFIRMATION=true
  elif [ -d "$arg" ]; then
    PERCORSO_SORGENTE=$(realpath "$arg")
  fi
done

if [ -z "$PERCORSO_SORGENTE" ]; then
  PERCORSO_SORGENTE="$PERCORSO_DESTINAZIONE"
  echo -e "${GREEN}### Inizio Script di Organizzazione Foto (Modalità In-Place) ###${NC}"
  echo "Libreria da organizzare: ${PERCORSO_DESTINAZIONE}"
else
  echo -e "${GREEN}### Inizio Script di Organizzazione Foto (Modalità Importazione) ###${NC}"
  echo "Sorgente: ${PERCORSO_SORGENTE}"
  echo "Destinazione: ${PERCORSO_DESTINAZIONE}"
fi

if [ "$IS_TEST_MODE" = true ]; then
    echo -e "\n${YELLOW}--- MODALITÀ TEST (DRY-RUN) ATTIVATA ---${NC}"
    TEST_DEST_DIR=$(mktemp -d -t photo_dest_test_XXXXXX)
    echo "Cartella di destinazione temporanea creata in: $TEST_DEST_DIR"
    TEST_SRC_DIR=$(mktemp -d -t photo_src_test_XXXXXX)
    echo "Copia di un campione di $NUM_TEST_FILES file dalla sorgente reale in: $TEST_SRC_DIR"
    find "$PERCORSO_SORGENTE" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.tif" -o -iname "*.mov" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" \) 2>/dev/null | shuf -n "$NUM_TEST_FILES" | xargs -I {} cp {} "$TEST_SRC_DIR"
    
    PERCORSO_SORGENTE="$TEST_SRC_DIR"
    PERCORSO_DESTINAZIONE="$TEST_DEST_DIR"
    DATABASE_FILE="${PERCORSO_DESTINAZIONE}/photo_library.sqlite"
    echo -e "${GREEN}Campionamento completato. Lo script simulerà lo spostamento da ${PERCORSO_SORGENTE} a ${PERCORSO_DESTINAZIONE}${NC}\n"
fi

# 2. CONTROLLI PRELIMINARI E SETUP
echo "[FASE 1/6] Esecuzione dei controlli preliminari..."
if ! command -v jdupes &> /dev/null; then echo -e "${RED}ERRORE: 'jdupes' non è installato.${NC}"; exit 1; fi
if ! command -v exiftool &> /dev/null; then echo -e "${RED}ERRORE: 'exiftool' non è installato.${NC}"; exit 1; fi
if ! command -v sqlite3 &> /dev/null; then echo -e "${RED}ERRORE: 'sqlite3' non è installato.${NC}"; exit 1; fi
if ! command -v sha256sum &> /dev/null; then echo -e "${RED}ERRORE: 'sha256sum' non è installato.${NC}"; exit 1; fi
if [ ! -d "$PERCORSO_SORGENTE" ]; then echo -e "${RED}ERRORE: Il percorso sorgente non esiste: $PERCORSO_SORGENTE${NC}"; exit 1; fi
if [ ! -d "$PERCORSO_DESTINAZIONE" ]; then mkdir -p "$PERCORSO_DESTINAZIONE"; fi

PERCORSO_VIDEO="$PERCORSO_DESTINAZIONE/$VIDEO_SUBDIR"
FALLBACK_IMG_DIR="$PERCORSO_DESTINAZIONE/nodate"
FALLBACK_VID_DIR="$PERCORSO_VIDEO/nodate"
mkdir -p "$PERCORSO_VIDEO" "$FALLBACK_IMG_DIR" "$FALLBACK_VID_DIR"
echo -e "${GREEN}Requisiti soddisfatti e directory preparate.${NC}\n"

# 3. INIZIALIZZAZIONE DATABASE
echo "[FASE 2/6] Inizializzazione del database SQLite in '${DATABASE_FILE}'..."
sqlite3 "$DATABASE_FILE" "
CREATE TABLE IF NOT EXISTS photos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sha256_hash TEXT NOT NULL UNIQUE,
    current_name TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    exif_date DATETIME,
    camera_model TEXT,
    date_added DATETIME NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_hash ON photos (sha256_hash);
"
echo -e "${GREEN}Database pronto.${NC}\n"

# 4. AVVISO E CONFERMA UTENTE
if [ "$IS_TEST_MODE" = false ] && [ "$SKIP_CONFIRMATION" = false ]; then
    echo -e "${YELLOW}⚠️ ATTENZIONE ⚠️${NC}"
    if [ "$PERCORSO_SORGENTE" == "$PERCORSO_DESTINAZIONE" ]; then
        echo "Lo script eseguirà operazioni ${RED}PERMANENTI${NC} sulla directory: ${YELLOW}${PERCORSO_DESTINAZIONE}${NC}"
    else
        echo "Lo script importerà i file da ${YELLOW}${PERCORSO_SORGENTE}${NC} a ${YELLOW}${PERCORSO_DESTINAZIONE}${NC}"
    fi
    echo "1. Eliminazione dei file duplicati nella sorgente."
    echo "2. Spostamento e indicizzazione dei file non ancora presenti nel database."
    echo -e "\n${YELLOW}Si raccomanda vivamente di avere un backup completo.${NC}"
    read -p "Sei sicuro di voler continuare? (s/N): " conferma
    if [[ "$conferma" != "s" && "$conferma" != "S" ]]; then echo "Operazione annullata."; exit 0; fi
    echo ""
elif [ "$SKIP_CONFIRMATION" = true ]; then
    echo -e "${GREEN}Modalità automatica attivata (conferma saltata).${NC}\n"
fi

# 5. ELIMINAZIONE DUPLICATI NELLA SORGENTE
echo "[FASE 3/6] ${GREEN}Eliminazione dei file duplicati esatti nella sorgente '${PERCORSO_SORGENTE}'...${NC}"
jdupes -r -d -N "$PERCORSO_SORGENTE"
echo -e "${GREEN}Eliminazione duplicati completata.${NC}\n"

# 6. PROCESSO PRINCIPALE FILE-PER-FILE
echo -e "[FASE 4/6] ${GREEN}Scansione della sorgente, organizzazione in destinazione e indicizzazione...${NC}"
echo "I file già presenti nel database di destinazione verranno saltati."

FILENAME_FORMAT='-filename=%f%c.%e'
VID_EXTENSIONS_REGEX=".*\.\(mov\|mp4\|avi\|mkv\)$"

find "$PERCORSO_SORGENTE" -type f -iregex ".*\.\(jpg\|jpeg\|png\|heic\|gif\|tif\|mov\|mp4\|avi\|mkv\)$" | while read -r file; do
    
    hash=$(sha256sum "$file" | awk '{print $1}')
    count=$(sqlite3 "$DATABASE_FILE" "SELECT COUNT(*) FROM photos WHERE sha256_hash = '$hash';")

    if [ "$count" -gt 0 ]; then
        echo "File già indicizzato, saltato: $(basename "$file")"
        continue
    fi

    echo "Nuovo file da processare: $(basename "$file")"
    
    exif_date=$(exiftool -s -s -s -d "%Y-%m-%d %H:%M:%S" -DateTimeOriginal "$file")
    camera_model=$(exiftool -s -s -s -Model "$file")
    file_size=$(stat -c %s "$file")
    current_name=$(basename "$file")
    dest_dir=""
    
    if [ -n "$exif_date" ]; then
        year=$(date -d "$exif_date" +%Y)
        month=$(date -d "$exif_date" +%m)
        day=$(date -d "$exif_date" +%d)
        
        if [[ $file =~ $VID_EXTENSIONS_REGEX ]]; then
            dest_dir="$PERCORSO_VIDEO/$year/$month/$day"
        else
            dest_dir="$PERCORSO_DESTINAZIONE/$year/$month/$day"
        fi
    else
        if [[ $file =~ $VID_EXTENSIONS_REGEX ]]; then
            dest_dir="$FALLBACK_VID_DIR"
        else
            dest_dir="$FALLBACK_IMG_DIR"
        fi
    fi

    mkdir -p "$dest_dir"
    
    exiftool -q -q "-directory=$dest_dir" $FILENAME_FORMAT "$file"
    
    new_file_path="$dest_dir/$current_name"
    relative_path="${new_file_path#$PERCORSO_DESTINAZIONE/}"
    
    sqlite3 "$DATABASE_FILE" "INSERT INTO photos (sha256_hash, current_name, relative_path, file_size_bytes, exif_date, camera_model, date_added) VALUES ('$hash', '${current_name//\'/''}', '$relative_path', $file_size, '${exif_date:-NULL}', '${camera_model//\'/''}', DATETIME('now'));"

done
echo -e "${GREEN}Processo completato.${NC}\n"

# 7. PULIZIA DELLE CARTELLE VUOTE
echo -e "[FASE 5/6] ${GREEN}Pulizia delle directory vuote residue...${NC}"
find "$PERCORSO_DESTINAZIONE" -mindepth 1 -type d -empty -delete
if [ "$PERCORSO_SORGENTE" != "$PERCORSO_DESTINAZIONE" ]; then
    find "$PERCORSO_SORGENTE" -mindepth 1 -type d -empty -delete
fi
echo -e "${GREEN}Pulizia completata.${NC}\n"

# 8. CONCLUSIONE
echo -e "[FASE 6/6] ${GREEN}Operazione terminata.${NC}\n"
if [ "$IS_TEST_MODE" = true ]; then
    echo -e "${YELLOW}Modalità Test terminata.${NC}"
    echo "Controlla il risultato nella cartella di destinazione temporanea:"
    echo "-> Foto e Video: $PERCORSO_DESTINAZIONE"
    echo "-> Database: $DATABASE_FILE"
    echo "La cartella sorgente temporanea è: $PERCORSO_SORGENTE"
    read -p "Vuoi eliminare le cartelle di test e tutto il loro contenuto? (s/N): " cleanup_confirm
    if [[ "$cleanup_confirm" == "s" || "$cleanup_confirm" == "S" ]]; then
        rm -rf "$PERCORSO_DESTINAZIONE"
        rm -rf "$PERCORSO_SORGENTE"
        echo "Cartelle di test eliminate."
    else
        echo "Le cartelle di test sono state conservate per l'analisi."
    fi
    echo -e "\n${GREEN}✅ Test completato!${NC}"
else
    echo -e "${GREEN}✅ Operazione terminata con successo!${NC}"
    echo "La tua libreria in '$PERCORSO_DESTINAZIONE' è stata aggiornata e indicizzata."
fi
