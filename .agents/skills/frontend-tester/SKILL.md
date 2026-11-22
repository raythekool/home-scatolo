---
name: frontend-tester
description: >-
  QA and verification agent for the Home Scatolo Flutter PWA (app/) and Admin Web Console
  (backend/src/admin/public/). Use whenever Flutter models, services, screens, or Admin HTML/CSS/JS
  change, or to audit API contract alignment, accessibility, and lint compliance.
---

# Frontend Tester — Home Scatolo QA Runbook

Verify both frontend surfaces of Home Scatolo:
1. **Flutter PWA** (`app/lib/`, `app/test/`)
2. **Admin Web Console** (`backend/src/admin/public/`)

## Automated Checks

1. Run the consolidated frontend QA script from the repository root:
   ```bash
   ./.agents/skills/frontend-tester/scripts/run-frontend-qa.sh
   ```
   This script verifies:
   - If `flutter` is installed: `flutter pub get`, `flutter analyze`, and `flutter test`.
   - Always (even without Flutter SDK): static invariant checks on `app/`:
     - No direct `sqflite` / `sqflite_common_ffi` imports outside `storage_service.dart`, `remote_storage_service.dart` (`show Database`), and `database_opener*.dart`.
     - `models/container.dart` is always imported aliased (`as models;`) to avoid shadowing Flutter's `Container`.
     - No hardcoded secret tokens in `app/lib/`.
     - Every public method of `StorageService` is implemented by `RemoteStorageService`.
   - Always on Admin Web Console (`backend/src/admin/public/`):
     - `node --check` on `app.js` and `qr.js`.
     - Zero `innerHTML` / `outerHTML` / `document.write` usage (XSS safety).
     - Accessibility checks: every `<input>`, `<select>`, `<textarea>` in `index.html` has an `id` with matching `<label for="...">` (or `type="hidden"`).

## Contract & UI Checklist

- **Flutter ↔ Backend API contract**: verify field names (`id`, `name`, `houseId`, `roomId`, `containerId`, `type`, `category`, `shortDescription`, `photoPath`, `insertedAt`, `quantity`) and routes (`/health`, `/recognize`, `/api/houses`, `/api/houses/:id/rooms`, `/api/rooms/:id/containers`, `/api/containers/:id/items`, `/api/items`, `/api/items/:id/increment`, `/api/quick-scan-container`, `/api/state/activeHouseId`, `/api/search`) match `backend/src/routes/inventory.ts` and `backend/src/recognition.ts`.
- **DI-for-tests pattern**: screens using `StorageService` keep optional test injection and never introduce external mocking packages.
- **Italian UX copy**: verify user-facing copy remains in consistent Italian.

## Output Format

Report:
1. Flutter toolchain status (`flutter analyze` / `flutter test` if available, or static audit results if SDK absent).
2. API contract alignment status (`RemoteStorageService` & `ApiClient` ↔ Backend).
3. Admin Web Console checks (JS syntax, XSS safety, accessibility, responsive layout).
4. Any defects or gaps found with exact file paths and line numbers.
