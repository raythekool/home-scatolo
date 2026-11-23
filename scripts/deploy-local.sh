#!/usr/bin/env bash
set -euo pipefail

# Build e avvio 100% locale sul MiniPC (zero GHCR, zero Flutter installato sull'host).
# Primo avvio:  ./scripts/deploy-local.sh
# Aggiornamento: ./scripts/deploy-local.sh --pull

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5vl:3b}"
INSTALL_BACKUP_CRON="${INSTALL_BACKUP_CRON:-1}"
DO_PULL=0

for arg in "$@"; do
  case "${arg}" in
    --pull) DO_PULL=1 ;;
    *)
      echo "Opzione sconosciuta: ${arg}" >&2
      echo "Uso: $0 [--pull]" >&2
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Errore: docker non trovato nel PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Errore: docker compose plugin non trovato." >&2
  exit 1
fi

cd "${REPO_DIR}"

if [ "${DO_PULL}" = "1" ]; then
  echo "==> Aggiornamento sorgenti da git"
  git pull --ff-only
fi

echo "==> Preparazione directory data/ e backups/"
mkdir -p "${REPO_DIR}/data" "${REPO_DIR}/backups"

if [ ! -f "${REPO_DIR}/.env" ]; then
  echo "==> Creazione .env iniziale da backend/.env.example"
  cp "${REPO_DIR}/backend/.env.example" "${REPO_DIR}/.env"

  if command -v openssl >/dev/null 2>&1; then
    generated_token="$(openssl rand -hex 32)"
  else
    generated_token="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
  fi
  sed -i "s|^APP_API_TOKEN=.*|APP_API_TOKEN=${generated_token}|" "${REPO_DIR}/.env"

  if [ -n "${GITHUB_MODELS_TOKEN:-}" ]; then
    sed -i "s|^GITHUB_MODELS_TOKEN=.*|GITHUB_MODELS_TOKEN=${GITHUB_MODELS_TOKEN}|" "${REPO_DIR}/.env"
  fi
  if [ -n "${PUBLIC_HOSTNAME:-}" ]; then
    sed -i "s|^ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=https://${PUBLIC_HOSTNAME},http://localhost:3000|" "${REPO_DIR}/.env"
  fi

  chmod 600 "${REPO_DIR}/.env"
  echo "    File ${REPO_DIR}/.env creato (permessi 600)."
  echo "    Provider AI configurati: github-models (primario) -> ollama (fallback)."
  if [ -z "${GITHUB_MODELS_TOKEN:-}" ]; then
    echo "    Nota: inserisci GITHUB_MODELS_TOKEN in ${REPO_DIR}/.env per usare GitHub Models come primario."
  fi
else
  echo "==> ${REPO_DIR}/.env gia' presente, nessuna sovrascrittura."
fi

if docker ps --format '{{.Names}}' | grep -qx 'ollama'; then
  echo "==> Container 'ollama' rilevato: verifico modello fallback ${OLLAMA_MODEL}"
  if ! docker exec ollama ollama list 2>/dev/null | awk '{print $1}' | grep -qx "${OLLAMA_MODEL}"; then
    echo "    Scarico ${OLLAMA_MODEL} su Ollama..."
    docker exec ollama ollama pull "${OLLAMA_MODEL}" || echo "    Avviso: pull Ollama non riuscito, riprova manualmente."
  else
    echo "    Modello ${OLLAMA_MODEL} gia' presente."
  fi
elif command -v ollama >/dev/null 2>&1; then
  echo "==> Ollama locale rilevato: verifico modello fallback ${OLLAMA_MODEL}"
  if ! ollama list 2>/dev/null | awk '{print $1}' | grep -qx "${OLLAMA_MODEL}"; then
    echo "    Scarico ${OLLAMA_MODEL} su Ollama..."
    ollama pull "${OLLAMA_MODEL}" || echo "    Avviso: pull Ollama non riuscito, riprova manualmente."
  else
    echo "    Modello ${OLLAMA_MODEL} gia' presente."
  fi
else
  echo "==> Ollama non rilevato (ne' container 'ollama' ne' binario locale); salto il pull automatico."
fi

echo "==> Build locale (PWA Flutter + Backend Node 22) e avvio container"
docker compose up -d --build --remove-orphans

echo "==> Verifica salute container"
for _ in $(seq 1 15); do
  if curl -fsS http://127.0.0.1:3000/livez >/dev/null 2>&1; then
    echo "    /livez OK"
    curl -sS http://127.0.0.1:3000/health || true
    echo ""
    break
  fi
  sleep 2
done

if [ "${INSTALL_BACKUP_CRON}" = "1" ]; then
  echo "==> Configurazione backup giornaliero SQLite (03:15, retention 14 giorni)"
  cat > "${REPO_DIR}/backup-db.sh" <<'BACKUP'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
stamp="$(date +%F-%H%M%S)"
target="/data/backup-${stamp}.db"
docker exec home-scatolo node -e "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('/data/inventory.db'); db.exec(\"VACUUM INTO '${target}'\"); db.close();"
mv "${APP_DIR}/data/backup-${stamp}.db" "${APP_DIR}/backups/inventory-${stamp}.db"
find "${APP_DIR}/backups" -name 'inventory-*.db' -mtime +14 -delete
BACKUP
  chmod 700 "${REPO_DIR}/backup-db.sh"
  cron_line="15 3 * * * ${REPO_DIR}/backup-db.sh >/dev/null 2>&1"
  (crontab -l 2>/dev/null | grep -v "${REPO_DIR}/backup-db.sh" || true; echo "${cron_line}") | crontab -
fi

echo ""
echo "Home Scatolo attivo in locale su http://127.0.0.1:3000"
echo "  - App PWA:       http://127.0.0.1:3000/"
echo "  - Console Admin: http://127.0.0.1:3000/admin"
echo "Per futuri aggiornamenti: ./scripts/deploy-local.sh --pull"
