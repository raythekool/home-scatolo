# Build all-in-one locale (PWA Flutter + Backend Node 22) senza GHCR ne' Flutter installato sull'host.
# Target: linux/amd64 (es. MiniPC Debian con Intel N97).
ARG FLUTTER_VERSION=3.50.1

FROM debian:bookworm-slim AS web-builder
ARG FLUTTER_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libglu1-mesa \
    unzip \
    xz-utils \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -s /bin/bash builder \
  && mkdir -p /opt /workspace/app \
  && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt \
  && chown -R builder:builder /opt/flutter /workspace

USER builder
ENV CI=true
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
ENV PUB_CACHE="/home/builder/.pub-cache"

RUN git config --global --add safe.directory /opt/flutter \
  && flutter --suppress-analytics config --enable-web \
  && flutter --suppress-analytics precache --web

WORKDIR /workspace/app
COPY --chown=builder:builder app/pubspec.yaml app/pubspec.lock ./
RUN flutter --suppress-analytics pub get

COPY --chown=builder:builder app/analysis_options.yaml ./
COPY --chown=builder:builder app/lib ./lib
COPY --chown=builder:builder app/web ./web

RUN flutter --suppress-analytics build web --release \
    --base-href / \
    --dart-define=STORAGE_MODE=remote \
    --dart-define=API_BASE_URL=

FROM node:22-alpine AS deps

WORKDIR /app
COPY backend/package*.json ./
RUN npm ci

FROM node:22-alpine AS runtime

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY backend/package*.json backend/tsconfig.json ./
COPY backend/src ./src
COPY --from=web-builder /workspace/app/build/web ./public

RUN mkdir -p /data

ENV NODE_ENV=production
ENV PORT=3000
ENV DB_PATH=/data/inventory.db
ENV PUBLIC_WEB_DIR=/app/public

VOLUME ["/data"]

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3000) + '/livez').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["npm", "start"]
