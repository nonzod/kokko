#!/bin/bash
# Pre-commit hook per scansionare secret con gitleaks
# Blocca il commit se vengono trovati dati sensibili

echo "🔍 Scansione secret con gitleaks..."

# Controlla se gitleaks è installato
if ! command -v gitleaks &> /dev/null; then
    echo "⚠️  gitleaks non trovato. Installalo con:"
    echo "   brew install gitleaks    # macOS"
    echo "   # o scarica da https://github.com/gitleaks/gitleaks/releases"
    exit 1
fi

# Scansiona solo le modifiche staged (quelle che stai per committare)
gitleaks protect --staged --verbose

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ GITLEAKS: Trovati potenziali secret nei file da committare!"
    echo ""
    echo "Opzioni:"
    echo "  1. Rimuovi i dati sensibili dai file"
    echo "  2. Usa 'git commit --no-verify' per forzare (NON CONSIGLIATO)"
    echo ""
    exit 1
fi

echo "✅ Nessun secret trovato. Commit approvato."
exit 0
