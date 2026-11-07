# Pipeline image: osmium-tool + osm2pgsql + pmtiles + the TypeScript CLI. Build context = repo root.
FROM node:24-bookworm-slim

ARG PMTILES_VERSION=1.31.2
ARG TARGETARCH
RUN apt-get update \
  && apt-get install -y --no-install-recommends osmium-tool osm2pgsql ca-certificates curl \
  && arch="$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x86_64)" \
  && curl -fsSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_${arch}.tar.gz" \
    | tar -xz -C /usr/local/bin pmtiles \
  && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
WORKDIR /repo
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/
COPY packages/geo/package.json packages/geo/
COPY pipeline/package.json pipeline/
RUN corepack enable && pnpm install --frozen-lockfile --filter pindoro --filter "@pindoro/pipeline..."

COPY tsconfig.base.json ./
COPY packages/geo packages/geo
COPY packages/pindoro_design/tokens packages/pindoro_design/tokens
COPY data data
COPY pipeline pipeline

WORKDIR /repo/pipeline
ENTRYPOINT ["/repo/node_modules/.bin/tsx", "src/cli.ts"]
