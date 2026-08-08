# 📦 Home Scatolo

> Inventario di casa con riconoscimento AI degli oggetti — multi-casa, multi-stanza, multi-scatolone.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Web%20%7C%20Android%20%7C%20iOS-informational)](#roadmap)
[![PWA](https://img.shields.io/badge/PWA-ready-5A0FC8?logo=pwa&logoColor=white)](#deploy-pwa)
[![AI](https://img.shields.io/badge/AI-GitHub%20Models-181717?logo=github&logoColor=white)](https://github.com/marketplace/models)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-in%20sviluppo-yellow.svg)](#roadmap)

**Home Scatolo** ti permette di fotografare armadi, scatoloni, librerie e contenitori di casa e ottenere automaticamente un inventario ricercabile, grazie al riconoscimento oggetti basato su AI (GitHub Models, es. GPT-4o vision).

## ✨ Funzionalità

- 📷 Cattura foto/video di contenitori (armadi, scatoloni, librerie, cassetti)
- 🤖 Riconoscimento automatico degli oggetti tramite AI (GitHub Models API)
- 🏠 Gestione **multi-casa**: configura più abitazioni/proprietà distinte
- 🚪 Organizzazione per stanza e contenitore all'interno di ogni casa
- 🔎 Ricerca full-text: "dove ho messo X?" senza aprire scatole a caso
- 📱 Disponibile come **PWA** (installabile da browser), con build native Android/iOS pianificate
- 💾 Storage locale offline-first, sync opzionale su cloud

## 🏗️ Architettura

```
home-scatolo/
├── app/              # Frontend Flutter (Web/PWA, Android, iOS)
│   ├── lib/
│   │   ├── models/       # Item, Container, Room, House
│   │   ├── screens/      # capture, inventory_list, item_detail, search, houses
│   │   ├── services/     # api_client, storage_service, camera_service
│   │   └── widgets/
│   └── web/          # manifest.json, icone PWA
├── backend/          # Funzione serverless: proxy verso GitHub Models
│   └── src/
│       ├── recognize.ts   # chiamata al modello vision
│       └── auth.ts        # gestione token (mai esposto al client)
├── docs/             # Documentazione tecnica e prompt versionati
└── .github/
    └── workflows/    # CI/CD: test, build PWA, deploy
```

Il frontend Flutter non chiama mai direttamente l'API AI con la chiave in chiaro: passa sempre da un backend leggero che nasconde il token GitHub Models, seguendo le best practice di sicurezza.

## 🚀 Stack tecnico

| Livello | Tecnologia |
|---|---|
| Frontend | Flutter (Web/PWA, Android, iOS) |
| Riconoscimento AI | [GitHub Models](https://github.com/marketplace/models) (GPT-4o / Llama Vision), via account Copilot Business |
| Backend | Funzione serverless (Node/TypeScript) da proxy per l'API AI |
| Storage locale | SQLite (`sqflite`) / Hive |
| CI/CD | GitHub Actions |
| Hosting PWA | GitHub Pages / Firebase Hosting |

## 🧰 Setup locale

### Prerequisiti

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x+
- [Node.js](https://nodejs.org/) 20+ (per il backend)
- Un account GitHub con accesso a [GitHub Models](https://github.com/marketplace/models) (Copilot Business consigliato per limiti più ampi)

### Frontend (Flutter)

```bash
cd app
flutter pub get
flutter run -d chrome        # sviluppo web/PWA
flutter run                  # sviluppo su device Android/iOS collegato
```

### Backend

```bash
cd backend
npm install
# Configura il token GitHub Models come variabile d'ambiente:
# GITHUB_MODELS_TOKEN=<il-tuo-token-con-scope-models:read>
npm run dev
```

> ⚠️ Non committare mai il token in chiaro. Usa un file `.env` (già escluso da `.gitignore`) o i Secrets di GitHub Actions in CI/CD.

## 📱 Deploy PWA

```bash
cd app
flutter build web --release --pwa-strategy offline-first
```

Il contenuto di `app/build/web` può essere pubblicato su GitHub Pages o Firebase Hosting. Il workflow `.github/workflows/deploy-pwa.yml` automatizza questo step ad ogni push su `main`.

## 🗺️ Roadmap

- [x] Definizione architettura e struttura repo
- [ ] Scaffold Flutter (Web + Android + iOS)
- [ ] Modello dati: House → Room → Container → Item
- [ ] Integrazione cattura foto/video
- [ ] Backend proxy verso GitHub Models
- [ ] Riconoscimento oggetti multi-item per singola foto
- [ ] Ricerca full-text sull'inventario
- [ ] Gestione multi-casa (switch tra proprietà)
- [ ] Deploy PWA su GitHub Pages
- [ ] Build nativa Android (Play Store)
- [ ] Build nativa iOS (TestFlight / App Store)

## 🤝 Contribuire

Progetto personale in sviluppo attivo. Issue e suggerimenti sono benvenuti.

## 📄 Licenza

Distribuito sotto licenza MIT. Vedi [LICENSE](LICENSE) per i dettagli.
