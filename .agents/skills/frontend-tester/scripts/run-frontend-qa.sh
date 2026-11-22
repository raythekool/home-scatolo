#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "${ROOT_DIR}"

echo "==> [1/4] Flutter static invariant checks"

# Check aliased Container model import
if grep -rnE "import '.*models/container\.dart';" app/lib/ app/test/ | grep -v "as models;"; then
  echo "ERROR: models/container.dart must be imported aliased (as models;)" >&2
  exit 1
fi

# Check direct sqflite imports outside approved files
bad_sqflite="$(grep -rn "package:sqflite" app/lib/ | grep -vE "storage_service\.dart|remote_storage_service\.dart|database_opener\.dart|database_opener_web\.dart" || true)"
if [ -n "${bad_sqflite}" ]; then
  echo "ERROR: Direct sqflite import outside platform-split files:" >&2
  echo "${bad_sqflite}" >&2
  exit 1
fi

# Check RemoteStorageService implements every Future method in StorageService
node -e "
const fs = require('node:fs');
const localSrc = fs.readFileSync('app/lib/services/storage_service.dart', 'utf8');
const remoteSrc = fs.readFileSync('app/lib/services/remote_storage_service.dart', 'utf8');
const methods = [...localSrc.matchAll(/^\s*Future<.+>\s+([a-z][A-Za-z0-9_]*)\s*\(/gm)].map(m => m[1]);
const missing = methods.filter(m => !new RegExp('Future<.+>\\\\s+' + m + '\\\\s*\\\\(').test(remoteSrc));
if (missing.length) {
  console.error('ERROR: RemoteStorageService missing methods:', missing.join(', '));
  process.exit(1);
}
console.log('Verified RemoteStorageService implements all ' + methods.length + ' StorageService methods.');
"

echo "==> [2/4] Admin Web Console syntax, XSS & A11y checks"
node --check backend/src/admin/public/app.js
node --check backend/src/admin/public/qr.js

if grep -rnE "\.(innerHTML|outerHTML)\s*=|document\.write\(" backend/src/admin/public/; then
  echo "ERROR: Unsafe DOM HTML sink found in Admin Web Console" >&2
  exit 1
fi

node -e "
const fs = require('node:fs');
const html = fs.readFileSync('backend/src/admin/public/index.html', 'utf8');
const inputs = [...html.matchAll(/<(input|select|textarea)\b([^>]*)>/g)];
const orphaned = [];
for (const [, tag, attrs] of inputs) {
  if (/type\s*=\s*\"hidden\"/i.test(attrs)) continue;
  const idMatch = /id\s*=\s*\"([^\"]+)\"/i.exec(attrs);
  if (!idMatch) { orphaned.push(tag + ' without id'); continue; }
  const id = idMatch[1];
  const hasLabel = new RegExp('<label[^>]*for\\s*=\\s*\"' + id + '\"', 'i').test(html);
  if (!hasLabel) orphaned.push(tag + '#' + id);
}
if (orphaned.length) {
  console.error('ERROR: Orphaned form controls without matching <label for>:', orphaned.join(', '));
  process.exit(1);
}
console.log('Verified all ' + inputs.length + ' form controls in admin/index.html have labels (or are hidden).');
"

echo "==> [3/4] Flutter SDK checks"
if command -v flutter >/dev/null 2>&1; then
  cd app
  flutter pub get
  flutter analyze
  flutter test
else
  echo "SKIP: flutter SDK not installed in this environment (verified in GitHub Actions flutter-ci.yml / deploy-minipc.yml)."
fi

echo "==> [4/4] Frontend QA PASSED."
