#!/usr/bin/env bash
set -euo pipefail

# Bootstrap one-shot (idempotente) per installare Home Scatolo sul MiniPC Debian 13.
# Dopo questo avvio, ogni push su `main` viene aggiornato automaticamente da Watchtower
# (oppure istantaneamente via SSH se abiliti MINIPC_DEPLOY_MODE=ssh in GitHub Actions).

APP_DIR="${APP_DIR:-/opt/home-scatolo}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/raythekool/home-scatolo/main}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5vl:3b}"
INSTALL_BACKUP_CRON="${INSTALL_BACKUP_CRON:-1}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Errore: docker non trovato nel PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Errore: docker compose plugin non trovato." >&2
  exit 1
fi

echo "==> Preparazione directory ${APP_DIR}"
mkdir -p "${APP_DIR}/data" "${APP_DIR}/backups"
cd "${APP_DIR}"

echo "==> Download docker-compose.minipc.yml e .env.example"
curl -fsSL "${REPO_RAW_BASE}/docker-compose.minipc.yml" -o docker-compose.minipc.yml
curl -fsSL "${REPO_RAW_BASE}/backend/.env.example" -o .env.example

if [ ! -f .env ]; then
  echo "==> Creazione .env iniziale con APP_API_TOKEN generato automaticamente"
  cp .env.example .env
  generated_token="$(openssl rand -hex 32)"
  sed -i "s|^APP_API_TOKEN=.*|APP_API_TOKEN=${generated_token}|" .env

  if [ -n "${GITHUB_MODELS_TOKEN:-}" ]; then
    sed -i "s|^GITHUB_MODELS_TOKEN=.*|GITHUB_MODELS_TOKEN=${GITHUB_MODELS_TOKEN}|" .env
  fi
  if [ -n "${PUBLIC_HOSTNAME:-}" ]; then
    sed -i "s|^ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=https://${PUBLIC_HOSTNAME},http://localhost:3000|" .env
  fi

  chmod 600 .env
  echo "    File ${APP_DIR}/.env creato (permessi 600)."
  echo "    APP_API_TOKEN generato automaticamente: conservalo per Hermes Agent / API."
  if [ -z "${GITHUB_MODELS_TOKEN:-}" ]; then
    echo "    Nota: aggiungi GITHUB_MODELS_TOKEN (o ANTHROPIC_API_KEY) in ${APP_DIR}/.env per il provider cloud primario."
  fi
else
  echo "==> ${APP_DIR}/.env gia' presente, nessuna sovrascrittura."
fi

if docker ps --format '{{.Names}}' | grep -qx 'ollama'; then
  echo "==> Container 'ollama' rilevato: verifico modello fallback ${OLLAMA_MODEL}"
  if ! docker exec ollama ollama list 2>/dev/null | awk '{print $1}' | grep -qx "${OLLAMA_MODEL}"; then
    echo "    Scarico ${OLLAMA_MODEL} su Ollama..."
    docker exec ollama ollama pull "${OLLAMA_MODEL}" || echo "    Avviso: pull Ollama non riuscito, riprova manualmente."
  else
    echo "    Modello ${OLLAMA_MODEL} gia' presente."
  fi
else
  echo "==> Container chiamato 'ollama' non trovato; salto il pull automatico del modello."
fi

echo "==> Avvio stack Home Scatolo + Watchtower"
docker compose -f docker-compose.minipc.yml pull
docker compose -f docker-compose.minipc.yml up -d --remove-orphans

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
  cat > "${APP_DIR}/backup-db.sh" <<'BACKUP'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
stamp="$(date +%F-%H%M%S)"
target="/data/backup-${stamp}.db"
docker exec home-scatolo node -e "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('/data/inventory.db'); db.exec(\"VACUUM INTO '${target}'\"); db.close();"
mv "${APP_DIR}/data/backup-${stamp}.db" "${APP_DIR}/backups/inventory-${stamp}.db"
find "${APP_DIR}/backups" -name 'inventory-*.db' -mtime +14 -delete
BACKUP
  chmod 700 "${APP_DIR}/backup-db.sh"
  cron_line="15 3 * * * ${APP_DIR}/backup-db.sh >/dev/null 2>&1"
  (crontab -l 2>/dev/null | grep -v "${APP_DIR}/backup-db.sh" || true; echo "${cron_line}") | crontab -
fi

echo ""
echo "Setup completato! Prossimo (e unico) step sul pannello Cloudflare:"
echo "  Tunnel -> Public Hostname -> es. scatolo.tuodominio.it -> http://127.0.0.1:3000"
