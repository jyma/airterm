FROM node:22-slim AS base
RUN npm install -g pnpm@10
WORKDIR /app

# Install dependencies
FROM base AS deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/
COPY packages/protocol/package.json packages/protocol/
COPY packages/crypto/package.json packages/crypto/
RUN pnpm install --frozen-lockfile

# Build
FROM deps AS build
COPY tsconfig.base.json ./
COPY packages/protocol/ packages/protocol/
COPY packages/crypto/ packages/crypto/
COPY apps/server/ apps/server/
RUN pnpm --filter @airterm/protocol build && \
    pnpm --filter @airterm/crypto build && \
    pnpm --filter @airterm/server build

# Production
FROM node:22-slim AS production
RUN npm install -g pnpm@10
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/apps/server/node_modules ./apps/server/node_modules
COPY --from=deps /app/packages/protocol/node_modules ./packages/protocol/node_modules
COPY --from=deps /app/packages/crypto/node_modules ./packages/crypto/node_modules
COPY --from=build /app/packages/protocol/dist ./packages/protocol/dist
COPY --from=build /app/packages/crypto/dist ./packages/crypto/dist
COPY --from=build /app/apps/server/src ./apps/server/src
COPY --from=build /app/package.json ./
COPY --from=build /app/pnpm-workspace.yaml ./
COPY --from=build /app/apps/server/package.json ./apps/server/
COPY --from=build /app/packages/protocol/package.json ./packages/protocol/
COPY --from=build /app/packages/crypto/package.json ./packages/crypto/

RUN mkdir -p /data

ENV PORT=3000
ENV DB_PATH=/data/airterm.db
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>r.ok?process.exit(0):process.exit(1))"

CMD ["npx", "tsx", "apps/server/src/index.ts"]
