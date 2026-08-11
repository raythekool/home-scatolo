# Home Scatolo — Agent Instructions

Home inventory app: photograph containers (wardrobes, boxes, shelves) and get an AI-generated
item inventory. Flutter frontend + a thin Node/Express backend that proxies GitHub Models
(never expose the AI token to the client). See [README.md](README.md) for product overview and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the data model and recognition flow.

Two independent projects, each with its own commands — always `cd` into the relevant one first.

## `app/` — Flutter frontend (Web/PWA, Android, iOS)

```bash
cd app
flutter pub get
flutter analyze     # lint, must pass (flutter_lints, see analysis_options.yaml)
flutter test         # run all tests before considering a change done
flutter run -d chrome  # local dev (web/PWA)
```

- **Layers**: `lib/models/` (plain data classes with `fromMap`/`toMap`/`copyWith`, no codegen) →
  `lib/services/` (`StorageService` for sqflite CRUD, `ApiClient` for the backend, `CameraService`,
  pure-logic `DuplicateMatcher`) → `lib/screens/` (`StatefulWidget`s calling services directly in
  `initState`/handlers, no Provider/Riverpod/Bloc).
- **DI-for-tests pattern**: screens take an optional constructor param (e.g. `storageService`) used
  only to inject fakes in tests; fakes are hand-written `implements StorageService` classes with
  `noSuchMethod` fallback (see [app/test/widget_test.dart](app/test/widget_test.dart)) — no mocking
  framework, don't introduce one.
- **sqflite is platform-split**: never import `sqflite`/`sqflite_common_ffi` directly — always go
  through the conditional import in
  [storage_service.dart](app/lib/services/storage_service.dart)
  (`database_opener.dart` for native, `database_opener_web.dart` for web via `dart.library.html`).
  Both must keep the same `openHomeScatoloDatabase(...)` signature.
- **DB schema changes**: bump `_dbVersion` and add an `onUpgrade` branch (see the v1→v2 pattern in
  `StorageService._openDb`) rather than dropping/recreating tables.
- `models/container.dart` shadows Flutter's `Container` widget — always import it aliased
  (`import '../models/container.dart' as models;`).
- Backend URL comes from `ApiClient(baseUrl: ...)` / `--dart-define=API_BASE_URL`, never hardcode
  secrets in client code.
- UI strings and test descriptions are in Italian — keep new UI text consistent with that locale.

## `backend/` — AI proxy (Node/TypeScript, Express)

```bash
cd backend
npm install
npm run dev    # tsx watch src/server.ts
npm test        # node --test, runs test/**/*.test.ts (node:test + node:assert/strict)
npm run build   # tsc --noEmit type-check only, no JS is emitted (runtime always uses tsx)
```

- Pure ESM (`"type": "module"`) + `NodeNext` resolution: relative imports must use `.js` extension
  even though the source is `.ts` (e.g. `import ... from './recognition.js'`).
- Required env var: `GITHUB_MODELS_TOKEN` (server throws if unset). Optional:
  `MODEL_NAME`, `GITHUB_MODELS_ENDPOINT`, `ALLOWED_ORIGINS`, `PORT`. Never commit a real token; use
  a local `.env` (gitignored).
- Only endpoint: `POST /recognize` — validated by `parseRecognitionRequest`/`parseRecognitionResult`
  in [recognition.ts](backend/src/recognition.ts) (`RecognitionValidationError` → HTTP 400). All
  other failures (missing token, fetch/model errors) return a generic HTTP 502 — never leak
  internal error details to the client.
- Tests only cover the pure validation functions in `recognition.ts`; there's no HTTP/network
  mocking for the GitHub Models `fetch` call in `server.ts`.
- ⚠️ [backend/README.md](backend/README.md) describes an older request/response contract
  (`image_base64`, `nome/categoria/descrizione_breve`) that no longer matches the code
  (`imageBase64`, `name/category/shortDescription`) — trust `recognition.ts`, not that README.

## CI

[.github/workflows/flutter-ci.yml](.github/workflows/flutter-ci.yml) runs `flutter analyze` +
`flutter test` on `app/**` changes. [.github/workflows/deploy-backend.yml](.github/workflows/deploy-backend.yml)
runs `npm run build`/`npm test` on manual dispatch. Match these commands locally before finishing a task.
