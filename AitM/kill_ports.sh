#!/bin/bash

# Script per terminare i processi sulle porte 443 e 5300
# Autore: Script generato automaticamente
# Data: $(date)

echo "=== Terminazione processi sulle porte 443 e 5300 ==="
echo

# Funzione per terminare processi su una porta specifica
kill_port() {
    local port=$1
    echo "Ricerca processi sulla porta $port..."
    
    # Trova i PID dei processi che usano la porta
    pids=$(lsof -ti:$port 2>/dev/null)
    
    if [ -z "$pids" ]; then
        echo "Nessun processo trovato sulla porta $port"
    else
        echo "Processi trovati sulla porta $port:"
        lsof -i:$port 2>/dev/null
        echo
        echo "Terminazione processi con PID: $pids"
        
        # Prova prima con SIGTERM (terminazione gentile)
        for pid in $pids; do
            if kill -0 $pid 2>/dev/null; then
                echo "Terminazione gentile del processo $pid..."
                kill -TERM $pid
                sleep 2
                
                # Se il processo è ancora attivo, forza la terminazione
                if kill -0 $pid 2>/dev/null; then
                    echo "Forzatura terminazione del processo $pid..."
                    kill -KILL $pid
                fi
            fi
        done
        
        # Verifica che i processi siano stati terminati
        sleep 1
        remaining=$(lsof -ti:$port 2>/dev/null)
        if [ -z "$remaining" ]; then
            echo "✅ Tutti i processi sulla porta $port sono stati terminati"
        else
            echo "⚠️ Alcuni processi sulla porta $port sono ancora attivi"
        fi
    fi
    echo "----------------------------------------"
}

# Verifica se l'utente ha i privilegi necessari
if [ "$EUID" -ne 0 ]; then
    echo "⚠️ Avviso: Potresti aver bisogno dei privilegi di root per terminare alcuni processi"
    echo "Se necessario, esegui lo script con 'sudo ./kill_ports.sh'"
    echo
fi

# Termina i processi sulle porte specificate
kill_port 443
kill_port 5300

echo "=== Operazione completata ==="
echo "Verifica finale delle porte:"
echo "Porta 443:"
lsof -i:443 2>/dev/null || echo "Nessun processo attivo"
echo "Porta 5300:"
lsof -i:5300 2>/dev/null || echo "Nessun processo attivo"
