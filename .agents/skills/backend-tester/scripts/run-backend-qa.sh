#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "${ROOT_DIR}/backend"

echo "==> [1/4] TypeScript strict check (npm run build)"
npm run build

echo "==> [2/4] Backend unit & integration tests (npm test)"
npm test

echo "==> [3/4] Admin Web ES Modules syntax check"
node --check src/admin/public/app.js
node --check src/admin/public/qr.js

echo "==> [4/4] Security log-leak check (no secrets or base64 logged)"
if grep -rnE "console\.(log|warn|error|info).*(imageBase64|APP_API_TOKEN|ADMIN_PASSWORD|GITHUB_MODELS_TOKEN|ANTHROPIC_API_KEY|GOOGLE_CLIENT_SECRET|authorization)" src/; then
  echo "ERROR: Potential secret or imageBase64 logged in backend/src/" >&2
  exit 1
fi

echo "Backend QA PASSED."
