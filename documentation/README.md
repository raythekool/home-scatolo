# 📚 Centro Documentazione — Home Scatolo

Benvenuto nella documentazione ufficiale di **Home Scatolo**, strutturata secondo il metodo **[Diátaxis](https://diataxis.fr/)**.

```text
                    PRATICA (Fare)
                         ▲
         ┌───────────────┴───────────────┐
         │  🎓 TUTORIAL                  │  🛠️ HOW-TO GUIDES
         │  GUIDA_USO.md                 │  GUIDA_USO.md
         │  Primo avvio & scansione      │  QR, Backup, Auth, Hermes
STUDIO ◄─┼───────────────────────────────┼─────────────────► LAVORO
         │  💡 EXPLANATION               │  📖 REFERENCE
         │  DOCUMENTAZIONE_TECNICA.md    │  DOCUMENTAZIONE_TECNICA.md
         │  Architettura, AI, Sicurezza  │  API REST, DB, Env, CI/CD
         └───────────────┬───────────────┘
                         ▼
                   TEORIA (Capire)
```

---

## 📑 Indice dei documenti

| Documento | Target | Contenuto principale |
| :--- | :--- | :--- |
| 📘 **[Guida d'Uso](GUIDA_USO.md)** | Utenti di casa & amministratori del MiniPC | Tutorial passo-passo, scansione AI, console `/admin` con screenshot reali, stampa etichette QR, backup/ripristino e interrogazioni da Hermes Agent / Home Assistant |
| 🏗️ **[Documentazione Tecnica](DOCUMENTAZIONE_TECNICA.md)** | Sviluppatori & sysadmin homelab | Diagrammi architetturali, data model SQLite + FTS5, pipeline Vision AI con fallback Ollama, sicurezza Zero Trust (Cloudflare RS256 / Google OAuth / Scoped Tokens), riferimento completo API REST e CI/CD |
| 🚀 **[Guida Deploy MiniPC](../docs/MINIPC_DEPLOY.md)** | Operazioni sul MiniPC Debian | Runbook compatto di bootstrap, Cloudflare Tunnel e manutenzione |
| 📋 **[Implementation Status](../docs/IMPLEMENTATION_STATUS.md)** | Handoff tecnico | Stato verificato di test, CI/CD, doppio tema Light/Dark e storico decisioni |
| 🎨 **[Figma UI & Design System](https://www.figma.com/design/dg84yVcT8nvTzX82zudH7g)** | Design & UI | Token WCAG AA+, Main Components, 4 schermate Flutter PWA e 3 viste Console `/admin` |
| 📮 **[Postman v3 Collection](../postman/collections/home-scatolo-api/)** | QA & Integrazioni API | Collezione eseguibile in Git + ambienti `Local Dev` e `MiniPC Vaiano` |

---

## 🖼️ Indice Asset Grafici (`assets/`)

- 🎨 [hero-home-scatolo.jpg](assets/hero-home-scatolo.jpg) — Illustrazione hero Home Scatolo + MiniPC
- 🗺️ [architecture-overview.svg](assets/architecture-overview.svg) — Diagramma architettura self-hosted completa
- 🗄️ [data-and-auth-flow.svg](assets/data-and-auth-flow.svg) — Diagramma modello dati SQLite/FTS5 e controllo accessi
- ⚙️ [cicd-and-vision-pipeline.svg](assets/cicd-and-vision-pipeline.svg) — Pipeline CI/CD Zero-Touch e flusso Vision AI + fallback Ollama
- 📸 [admin-overview.png](assets/admin-overview.png) — Screenshot Console Admin: *Panoramica & AI*
- 📸 [admin-inventory.png](assets/admin-inventory.png) — Screenshot Console Admin: *Inventario & Spazi*
- 📸 [admin-qr.png](assets/admin-qr.png) — Screenshot Console Admin: *Etichette QR*
- 📸 [admin-system.png](assets/admin-system.png) — Screenshot Console Admin: *Sistema, Backup & API*
