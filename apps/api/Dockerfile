# syntax=docker/dockerfile:1
# Build from the repo root: docker build -f apps/api/Dockerfile .

FROM node:24-bookworm-slim AS build
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
WORKDIR /repo
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/geo/package.json packages/geo/
COPY apps/pipeline/package.json apps/pipeline/
COPY apps/api apps/api
# --legacy: the API has no workspace dependencies, so nothing needs injecting.
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm --filter @pindoro/api deploy --prod --legacy /out

FROM node:24-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /out ./
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/health').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
# Node 24 strips TypeScript types natively; there is no build step.
CMD ["node", "src/server.ts"]
