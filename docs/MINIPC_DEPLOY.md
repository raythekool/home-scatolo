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
summary: Guida operativa per installare Home Scatolo sul MiniPC Debian 13 con SQLite persistente, GitHub Models + Ollama fallback e Cloudflare Tunnel.
post_date: 2026-11-22
---

# Deploy Self-Hosted su MiniPC (Debian 13 + Docker)

Questa guida copre il deploy **completamente automatizzato** di Home Scatolo (PWA Flutter + Backend Node 22 + SQLite persistente + AI cloud con fallback Ollama locale) sul MiniPC Debian 13, esposto via **Cloudflare Tunnel**.

## Architettura della Pipeline CI/CD

Ad ogni push su `main` (o avvio manuale da GitHub Actions), il workflow [deploy-minipc.yml](../.github/workflows/deploy-minipc.yml):

1. Esegue `flutter analyze`, `flutter test` e compila la PWA Flutter in modalità `STORAGE_MODE=remote` (same-origin, zero CORS).
2. Esegue `npm run build` e `npm test` sul backend.
3. Costruisce l'immagine Docker all-in-one ([Dockerfile.minipc](../Dockerfile.minipc)) per `linux/amd64` (Intel N97) con backend + PWA inclusa e la pubblica su **GitHub Container Registry** (`ghcr.io/raythekool/home-scatolo:latest` + tag `:sha-...`).
4. Aggiorna automaticamente il MiniPC in uno di due modi:
   - **Default (zero porte aperte / zero chiavi SSH)**: **Watchtower** in [docker-compose.minipc.yml](../docker-compose.minipc.yml) (limitato **solo** al container `home-scatolo` via label `com.centurylinklabs.watchtower.enable=true`) controlla ogni 5 minuti, scarica la nuova immagine, riavvia il container e pulisce le immagini vecchie.
   - **Opzionale (deploy istantaneo via SSH)**: impostando la variable GitHub Actions `MINIPC_DEPLOY_MODE=ssh` e i secrets `MINIPC_SSH_HOST`, `MINIPC_SSH_USER`, `MINIPC_SSH_KEY` (e opzionale `MINIPC_SSH_PORT`, `MINIPC_APP_DIR`).

## 1. Primo bootstrap sul MiniPC (una volta sola)

Dopo il primo push su `main` (che pubblica l'immagine su GHCR — rendi il package pubblico su GitHub Packages oppure esegui `docker login ghcr.io` sul MiniPC), lancia sul MiniPC un solo comando:

```bash
PUBLIC_HOSTNAME=scatolo.tuodominio.it \
GITHUB_MODELS_TOKEN=<il-tuo-pat-models-read> \
curl -fsSL https://raw.githubusercontent.com/raythekool/home-scatolo/main/scripts/bootstrap-minipc.sh | bash
```

Lo script [bootstrap-minipc.sh](../scripts/bootstrap-minipc.sh) è idempotente e in automatico:
- crea `/opt/home-scatolo/{data,backups}` e scarica `docker-compose.minipc.yml`;
- genera `.env` (permessi `600`) con un `APP_API_TOKEN` casuale;
- rileva il container `ollama` esistente e scarica `qwen2.5vl:3b` come fallback vision;
- avvia `home-scatolo` + `watchtower` e verifica `/livez` e `/health`;
- imposta un cron giornaliero (03:15) per il backup consistente SQLite (`VACUUM INTO`) con retention di 14 giorni.

> [!TIP]
> Se preferisci costruire l'immagine direttamente sul MiniPC senza GHCR, resta disponibile [docker-compose.yml](../docker-compose.yml) per build locale da sorgente.

## 2. Esposizione sicura via Cloudflare Tunnel + Social Login Google

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

## 3. Interrogare l'inventario da Hermes Agent / Home Assistant

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

## 4. Verifica e backup manuale

```bash
curl http://127.0.0.1:3000/livez
curl http://127.0.0.1:3000/health
/opt/home-scatolo/backup-db.sh
```
