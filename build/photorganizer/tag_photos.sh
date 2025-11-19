#!/bin/bash

# ==============================================================================
# Progetto: QNAP Photo Tagger
# Descrizione: Script per taggare automaticamente le foto usando ollama-img-tagger
# Versione: 1.0
# ==============================================================================

# --- CONFIGURAZIONE ---
PERCORSO_DESTINAZIONE="${PHOTO_DESTINATION_PATH:-/mnt/photos_destination}"
VIDEO_SUBDIR="${VIDEO_SUBDIR_NAME:-Videos}"
OLLAMA_HOST="${OLLAMA_HOST:-192.168.178.100}"
NUM_TEST_FILES="${NUM_TEST_FILES:-10}"

# --- INIZIO SCRIPT ---

# Colori
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
IS_TEST_MODE=false
SKIP_CONFIRMATION=false
PERCORSO_TAGGING=""
PARALLEL_JOBS=4

# 1. GESTIONE ARGOMENTI E AVVIO
for arg in "$@"; do
  if [[ "$arg" == "--test" || "$arg" == "-t" ]]; then
    IS_TEST_MODE=true
  elif [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
    SKIP_CONFIRMATION=true
  elif [[ "$arg" =~ ^-j[0-9]+$ ]]; then
    PARALLEL_JOBS="${arg:2}"
  elif [ -d "$arg" ]; then
    PERCORSO_TAGGING=$(realpath "$arg")
  fi
done

if [ -z "$PERCORSO_TAGGING" ]; then
  PERCORSO_TAGGING="$PERCORSO_DESTINAZIONE"
fi

echo -e "${GREEN}### Inizio Script di Tagging Foto ###${NC}"
echo "Directory da processare: ${PERCORSO_TAGGING}"
echo "Host Ollama: ${OLLAMA_HOST}"
echo "Job paralleli: ${PARALLEL_JOBS}"

if [ "$IS_TEST_MODE" = true ]; then
    echo -e "\n${YELLOW}--- MODALITÀ TEST ATTIVATA ---${NC}"
    echo "Saranno processati solo $NUM_TEST_FILES file casuali"
fi

# 2. CONTROLLI PRELIMINARI
echo -e "\n[FASE 1/4] Esecuzione dei controlli preliminari..."

if ! command -v ./ollama-img-tagger &> /dev/null; then
    echo -e "${RED}ERRORE: 'ollama-img-tagger' non è disponibile nella directory corrente.${NC}"
    exit 1
fi

if [ ! -d "$PERCORSO_TAGGING" ]; then
    echo -e "${RED}ERRORE: Il percorso non esiste: $PERCORSO_TAGGING${NC}"
    exit 1
fi

# Test connessione a Ollama
echo "Verifica connessione a Ollama su ${OLLAMA_HOST}..."
if ! timeout 5 bash -c "echo > /dev/tcp/${OLLAMA_HOST}/11434" 2>/dev/null; then
    echo -e "${YELLOW}AVVISO: Impossibile connettersi a ${OLLAMA_HOST}:11434. Il tagging potrebbe fallire.${NC}"
    read -p "Vuoi continuare comunque? (s/N): " continue_anyway
    if [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]]; then
        echo "Operazione annullata."
        exit 0
    fi
fi

echo -e "${GREEN}Requisiti soddisfatti.${NC}\n"

# 3. AVVISO E CONFERMA UTENTE
if [ "$IS_TEST_MODE" = false ] && [ "$SKIP_CONFIRMATION" = false ]; then
    echo -e "${YELLOW}⚠️ ATTENZIONE ⚠️${NC}"
    echo "Lo script eseguirà il tagging di tutte le foto in: ${YELLOW}${PERCORSO_TAGGING}${NC}"
    echo "Questo processo potrebbe richiedere molto tempo a seconda del numero di foto."
    echo ""
    read -p "Sei sicuro di voler continuare? (s/N): " conferma
    if [[ "$conferma" != "s" && "$conferma" != "S" ]]; then
        echo "Operazione annullata."
        exit 0
    fi
    echo ""
elif [ "$SKIP_CONFIRMATION" = true ]; then
    echo -e "${GREEN}Modalità automatica attivata (conferma saltata).${NC}\n"
fi

# 4. RACCOLTA FILE DA PROCESSARE
echo "[FASE 2/4] ${GREEN}Raccolta file da processare...${NC}"

# Estensioni immagini supportate (escludo i video)
IMG_EXTENSIONS_PATTERN=".*\.\(jpg\|jpeg\|png\|heic\|gif\|tif\|tiff\|bmp\|webp\)$"

if [ "$IS_TEST_MODE" = true ]; then
    echo "Selezione casuale di $NUM_TEST_FILES file per il test..."
    TEMP_FILE_LIST=$(mktemp)
    find "$PERCORSO_TAGGING" -type f -iregex "$IMG_EXTENSIONS_PATTERN" 2>/dev/null | shuf -n "$NUM_TEST_FILES" > "$TEMP_FILE_LIST"
    TOTAL_FILES=$(wc -l < "$TEMP_FILE_LIST")
else
    TEMP_FILE_LIST=$(mktemp)
    find "$PERCORSO_TAGGING" -type f -iregex "$IMG_EXTENSIONS_PATTERN" 2>/dev/null > "$TEMP_FILE_LIST"
    TOTAL_FILES=$(wc -l < "$TEMP_FILE_LIST")
fi

echo -e "${GREEN}Trovati ${TOTAL_FILES} file da processare.${NC}\n"

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo -e "${YELLOW}Nessun file da processare. Uscita.${NC}"
    rm -f "$TEMP_FILE_LIST"
    exit 0
fi

# 5. PROCESSO TAGGING
echo "[FASE 3/4] ${GREEN}Inizio tagging delle immagini...${NC}"
echo "Questo potrebbe richiedere del tempo..."
echo ""

PROCESSED=0
SUCCESSFUL=0
FAILED=0

# Funzione per processare un singolo file
process_file() {
    local file="$1"
    local current="$2"
    local total="$3"

    echo -e "${BLUE}[$current/$total]${NC} Tagging: $(basename "$file")"

    if ./ollama-img-tagger -h "$OLLAMA_HOST" "$file" 2>&1; then
        echo -e "${GREEN}✓ Completato: $(basename "$file")${NC}"
        return 0
    else
        echo -e "${RED}✗ Errore: $(basename "$file")${NC}"
        return 1
    fi
}

export -f process_file
export OLLAMA_HOST GREEN RED BLUE NC

# Processo i file con GNU parallel se disponibile, altrimenti in sequenza
if command -v parallel &> /dev/null && [ "$PARALLEL_JOBS" -gt 1 ]; then
    echo "Utilizzo di GNU parallel con $PARALLEL_JOBS job paralleli"
    echo ""

    cat "$TEMP_FILE_LIST" | parallel -j "$PARALLEL_JOBS" --line-buffer --bar \
        'if ./ollama-img-tagger -h '"$OLLAMA_HOST"' {} 2>&1 > /dev/null; then echo "OK"; else echo "FAIL"; fi' | \
    while read -r result; do
        PROCESSED=$((PROCESSED + 1))
        if [ "$result" = "OK" ]; then
            SUCCESSFUL=$((SUCCESSFUL + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    done
else
    # Processo sequenziale
    while IFS= read -r file; do
        PROCESSED=$((PROCESSED + 1))

        echo -e "${BLUE}[$PROCESSED/$TOTAL_FILES]${NC} Tagging: $(basename "$file")"

        if ./ollama-img-tagger -h "$OLLAMA_HOST" "$file" 2>&1; then
            SUCCESSFUL=$((SUCCESSFUL + 1))
            echo -e "${GREEN}✓ Completato${NC}"
        else
            FAILED=$((FAILED + 1))
            echo -e "${RED}✗ Errore${NC}"
        fi

        echo ""
    done < "$TEMP_FILE_LIST"
fi

# 6. PULIZIA
rm -f "$TEMP_FILE_LIST"

# 7. CONCLUSIONE
echo -e "\n[FASE 4/4] ${GREEN}Operazione terminata.${NC}\n"
echo "=========================================="
echo "STATISTICHE FINALI"
echo "=========================================="
echo "File processati:  $PROCESSED"
echo -e "${GREEN}Successi:        $SUCCESSFUL${NC}"
if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Falliti:         $FAILED${NC}"
else
    echo "Falliti:         $FAILED"
fi
echo "=========================================="

if [ "$IS_TEST_MODE" = true ]; then
    echo -e "\n${GREEN}✅ Test completato!${NC}"
else
    echo -e "\n${GREEN}✅ Tagging completato!${NC}"
fi
