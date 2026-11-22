---
name: backend-tester
description: >-
  QA and automated testing agent for the Home Scatolo Node.js 22 / Express 5 / SQLite FTS5
  backend. Use whenever backend routes, auth, SQLite schema, Vision AI providers, or admin
  APIs are modified, or when running a full backend regression and security audit.
---

# Backend Tester — Home Scatolo QA Runbook

Verify type safety, automated tests, security invariants, and live HTTP behavior for `backend/`.

## Automated Checks

1. Run the consolidated QA script from the repository root:
   ```bash
   ./.agents/skills/backend-tester/scripts/run-backend-qa.sh
   ```
   This script runs:
   - `npm run build` (`tsc --noEmit` strict check)
   - `npm test` (all `node:test` suites in `backend/test/`)
   - `node --check` on Admin Console ES modules (`src/admin/public/app.js`, `qr.js`)
   - Security grep audit ensuring `imageBase64`, `APP_API_TOKEN`, `GITHUB_MODELS_TOKEN`, `ANTHROPIC_API_KEY`, and `Authorization` headers are never logged in `backend/src/`
   - Ephemeral live HTTP smoke test against `createApp` (`/livez`, `/health`, `/admin`, `/api/houses`, `/api/search`)

## Regression Checklist

When reviewing or adding backend changes, verify:
- **SQLite integrity**: foreign keys (`ON DELETE CASCADE`), FTS5 triggers stay synced after `INSERT`/`UPDATE`/`DELETE`, and backups work via `VACUUM INTO`.
- **RBAC isolation**: `read` API tokens cannot mutate `/api/*` or reach `/api/admin/*`; `write` API tokens cannot reach `/api/admin/*`; Cloudflare Access JWTs require valid RS256 signature, `aud`, `iss`, and `exp`.
- **Vision fallback**: provider failures (network, timeout, 429/5xx, malformed JSON) fall back cleanly without leaking upstream error details or Base64 payloads (generic HTTP `502` on total failure, HTTP `400` on validation errors).
- **Relative ESM imports**: all TypeScript relative imports in `backend/src/` and `backend/test/` use `.js` extensions (`NodeNext`).

## Output Format

Report:
1. Pass/fail status of `npm run build`, `npm test` (exact test count), syntax checks, and security audit.
2. Any regressions, edge cases, or missing tests discovered (with exact file paths and line numbers).
3. Concrete fixes applied or recommended.
