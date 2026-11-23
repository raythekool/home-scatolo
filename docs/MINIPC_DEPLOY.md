---
post_title: Home Scatolo MiniPC Self-Hosted Deploy
author1: Marco Dodaro
post_slug: home-scatolo-minipc-deploy
microsoft_alias: not-applicable
featured_image: ''
categories:
  - documentation
tags:
  - docker
  - self-hosted
  - ollama
  - cloudflare-tunnel
summary: Guida operativa per installare Home Scatolo sul MiniPC Debian 13 con build Docker 100% locale (privata), SQLite persistente, GitHub Models + Ollama fallback e Cloudflare Tunnel.
post_date: 2026-11-23
---

<!-- markdownlint-disable MD041 -->

## Deploy Self-Hosted su MiniPC (Debian 13 + Docker)

Questa guida copre il deploy privato di Home Scatolo (PWA Flutter + Backend Node 22 + SQLite persistente + AI Vision con **GitHub Models primario** e **Ollama locale fallback**) sul MiniPC Debian 13.

## 1. Build 100% locale da sorgente (consigliata per uso privato, zero GHCR)

Non richiede alcun package pubblico su GHCR né l'installazione di Flutter sul MiniPC: il [Dockerfile](../Dockerfile) multi-stage compila sia la PWA Flutter (`STORAGE_MODE=remote`, same-origin) sia il backend Node 22 direttamente sul MiniPC.

```bash
git clone https://github.com/raythekool/home-scatolo.git /opt/home-scatolo
cd /opt/home-scatolo

GITHUB_MODELS_TOKEN=<il-tuo-pat-models-read> \
./scripts/deploy-local.sh
```

Lo script [deploy-local.sh](../scripts/deploy-local.sh) è idempotente e in automatico:

- crea `./data` e `./backups`;
- genera `./.env` (permessi `600`) da `backend/.env.example` con `APP_API_TOKEN` casuale e `AI_PRIMARY_PROVIDER=github-models` → `AI_FALLBACK_PROVIDER=ollama`;
- rileva Ollama (container `ollama` o installazione host) e scarica `qwen2.5vl:3b` come fallback vision;
- compila l'immagine locale e avvia `home-scatolo` via [docker-compose.yml](../docker-compose.yml) (la prima build Flutter richiede ~3–5 minuti, le successive sfruttano la cache Docker);
- verifica `/livez` e `/health` e configura il cron giornaliero (03:15) di backup SQLite (`VACUUM INTO`, retention 14 giorni).

Per aggiornare in seguito dopo nuove modifiche:

```bash
cd /opt/home-scatolo
./scripts/deploy-local.sh --pull
```

> [!TIP]
> Se vuoi raggiungere l'app direttamente dagli altri dispositivi in LAN senza Cloudflare Tunnel, in [docker-compose.yml](../docker-compose.yml) cambia `"127.0.0.1:3000:3000"` in `"3000:3000"` e rilancia `docker compose up -d`.

## 2. Alternativa opzionale: immagine precompilata su GHCR + Watchtower

Se in futuro preferisci delegare la compilazione a GitHub Actions ([deploy-minipc.yml](../.github/workflows/deploy-minipc.yml)) e usare Watchtower sul MiniPC con [docker-compose.minipc.yml](../docker-compose.minipc.yml) e [Dockerfile.minipc](../Dockerfile.minipc):

```bash
PUBLIC_HOSTNAME=scatolo.tuodominio.it \
GITHUB_MODELS_TOKEN=<il-tuo-pat-models-read> \
curl -fsSL https://raw.githubusercontent.com/raythekool/home-scatolo/main/scripts/bootstrap-minipc.sh | bash
```

Per mantenere il package `ghcr.io/raythekool/home-scatolo` privato in questa modalità, esegui prima `docker login ghcr.io` sul MiniPC con un PAT `read:packages` e monta `/root/.docker/config.json:/config.json:ro` nel servizio `watchtower`.

## 3. Esposizione sicura via Cloudflare Tunnel + Social Login Google

Nel pannello **Cloudflare Zero Trust → Networks → Tunnels → (tuo tunnel) → Public Hostname**:
- **Subdomain / Domain**: es. `scatolo.tuodominio.it`
- **Service**: `HTTP` → `127.0.0.1:3000` (oppure `home-scatolo:3000` se `cloudflared` condivide la rete Docker)

### Console Amministrativa (`/admin`) e Login con Google

La console amministrativa è raggiungibile su `https://scatolo.tuodominio.it/admin` e supporta tre modalità di autenticazione (anche combinabili):

1. **Google Login tramite Cloudflare Access (consigliata, zero credenziali OAuth da gestire nell'app)**:
   - In **Cloudflare Zero Trust → Settings → Authentication → Login methods**, aggiungi **Google**.
   - Crea una **Reusable Policy** (`Allow` solo per la tua email Gmail) e collegala a una Self-hosted Application su `scatolo.tuodominio.it`.
   - Copia **Team Domain** (`tuoteam.cloudflareaccess.com`) e **Application Audience (AUD) Tag** in `.env`:
     ```env
     CF_ACCESS_TEAM_DOMAIN=tuoteam.cloudflareaccess.com
     CF_ACCESS_AUD=<aud-tag>
     AUTH_ALLOWED_EMAILS=tua.email@gmail.com
     ```
   - Il backend verifica crittograficamente il JWT `Cf-Access-Jwt-Assertion` (RS256 contro `/cdn-cgi/access/certs`) e ti autentica automaticamente sia sulla PWA (`/`) sia sulla console `/admin` senza un secondo login.
2. **Google Social Login OAuth 2.0 diretto** (alternativa senza Cloudflare Access):
   - Crea un client OAuth Web su Google Cloud Console con redirect URI `https://scatolo.tuodominio.it/api/auth/google/callback`.
   - Imposta in `.env`: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` e `AUTH_ALLOWED_EMAILS=tua.email@gmail.com`.
   - Su `/admin` apparirà il pulsante **Accedi con Google**, che emette un cookie di sessione `HttpOnly` valido sia per `/admin` sia per la PWA sullo stesso origin.
3. **Password locale + Token API dedicati**:
   - Puoi sempre accedere da LAN con `ADMIN_PASSWORD` (o `APP_API_TOKEN`).
   - Nella tab **Sistema, Backup & API** di `/admin` puoi generare token API con permesso **read-only** dedicati a **Hermes Agent** e **Home Assistant** (in LAN su `http://127.0.0.1:3000` o `http://home-scatolo:3000`, senza mai esporre le credenziali admin).

## 4. Interrogare l'inventario da Hermes Agent / Home Assistant

Tutte le API rispondono in JSON e accettano `Authorization: Bearer <APP_API_TOKEN>` o `X-Api-Key: <APP_API_TOKEN>`:

```bash
# "Dove ho messo il cavo HDMI?"
curl -H "X-Api-Key: $APP_API_TOKEN" \
  "http://127.0.0.1:3000/api/search?q=hdmi"

# Export completo JSON (utile per snapshot/backup o indicizzazione)
curl -H "X-Api-Key: $APP_API_TOKEN" \
  "http://127.0.0.1:3000/api/export" > inventory-backup.json
```

Ogni risultato di `/api/search` include il percorso completo: `houseName`, `roomName`, `containerName`, `containerType`, `quantity`, `shortDescription`, `notes`.

## 5. Verifica e backup manuale

```bash
curl http://127.0.0.1:3000/livez
curl http://127.0.0.1:3000/health
/opt/home-scatolo/backup-db.sh
```
