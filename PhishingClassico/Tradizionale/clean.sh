
# Script per pulire credenziali e log di debug
# Uso: ./clean.sh

echo "Pulizia dei file di credenziali e debug in corso..."

# Contatori
credenziali_pulite=0
log_puliti=0

echo "Pulizia cartella credenziali..."

# Pulisce tutti i file delle credenziali
if [ -d "credenziali" ]; then
    for file in credenziali/*.txt; do
        if [ -f "$file" ]; then
            > "$file"
            echo "  Pulito: $(basename "$file")"
            ((credenziali_pulite++))
        fi
    done
else
    echo "  Cartella credenziali non trovata"
fi

echo "Pulizia cartella debug..."

# Pulisce tutti i file di log nella cartella debug
if [ -d "debug" ]; then
    for file in debug/*.log debug/*.txt; do
        if [ -f "$file" ]; then
            > "$file"
            echo "  Pulito: $(basename "$file")"
            ((log_puliti++))
        fi
    done
    
    # Rimuove file .bak
    for file in debug/*.bak; do
        if [ -f "$file" ]; then
            rm "$file"
            echo "  Rimosso: $(basename "$file")"
            ((log_puliti++))
        fi
    done
else
    echo "  Cartella debug non trovata"
fi

# Pulisce cache Python
if [ -d "__pycache__" ]; then
    echo "Pulizia cache Python..."
    rm -rf __pycache__
    echo "  Cache Python rimossa"
fi

echo "Pulizia completata!"
echo "File credenziali puliti: ${credenziali_pulite}"
echo "File di log puliti: ${log_puliti}"
echo "Sistema pronto per un nuovo test."
