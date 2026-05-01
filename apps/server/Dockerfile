# syntax=docker/dockerfile:1.6
#
# Two-stage build: install + compile native deps in a builder, then ship
# a slim runtime image with just `dist/` + production node_modules.
#
# better-sqlite3 is a native module that needs python + a C++ toolchain
# at install time — the runtime stage drops both.

ARG NODE_VERSION=22

# ----- Stage 1: dependencies -----
FROM node:${NODE_VERSION}-bookworm-slim AS deps

# Build deps for native modules (better-sqlite3, @journeyapps/sqlcipher).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 make g++ build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# pnpm via corepack — pinned to the version this repo uses so a host-image
# upgrade doesn't silently switch package-manager behaviour under us.
RUN corepack enable && corepack prepare pnpm@10.6.5 --activate

# Bring just enough of the workspace in to install (full source comes
# next so a dep-only change still hits the docker layer cache).
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml tsconfig.base.json ./
COPY packages/protocol/package.json packages/protocol/tsconfig.json packages/protocol/
COPY packages/crypto/package.json   packages/crypto/tsconfig.json   packages/crypto/
COPY apps/server/package.json       apps/server/tsconfig.json       apps/server/

RUN pnpm install --frozen-lockfile --filter @airterm/server... --prod=false

# ----- Stage 2: build -----
FROM deps AS build

COPY packages/protocol/src packages/protocol/src
COPY packages/crypto/src   packages/crypto/src
COPY apps/server/src       apps/server/src

# Build the protocol + crypto packages first so server's tsc finds their
# emitted `.d.ts` + `.js`.
RUN pnpm --filter @airterm/protocol build \
 && pnpm --filter @airterm/crypto   build \
 && pnpm --filter @airterm/server   build

# ----- Stage 3: runtime -----
FROM node:${NODE_VERSION}-bookworm-slim AS runtime

# better-sqlite3 ships a prebuilt binary so we don't need the C++
# toolchain at runtime; just libstdc++ which the slim image already has.

WORKDIR /app

# pnpm at runtime so we can `pnpm --filter ... start` in case the
# user wants to run it that way; the canonical entry below uses
# `node` directly so the image works even without pnpm.
RUN corepack enable && corepack prepare pnpm@10.6.5 --activate

# Copy only what runtime needs: built dist/, package manifests, and
# the production node_modules tree.
COPY --from=build /workspace/pnpm-workspace.yaml ./
COPY --from=build /workspace/package.json ./
COPY --from=build /workspace/pnpm-lock.yaml ./
COPY --from=build /workspace/packages/protocol/package.json packages/protocol/
COPY --from=build /workspace/packages/protocol/dist        packages/protocol/dist
COPY --from=build /workspace/packages/crypto/package.json  packages/crypto/
COPY --from=build /workspace/packages/crypto/dist          packages/crypto/dist
COPY --from=build /workspace/apps/server/package.json      apps/server/
COPY --from=build /workspace/apps/server/dist              apps/server/dist

# Re-install with --prod so we drop dev deps + recompile native modules
# against the runtime image's node ABI (matches what was installed in deps).
RUN pnpm install --frozen-lockfile --filter @airterm/server... --prod \
 && pnpm store prune

# AirTerm's relay listens on a single port for both HTTP (pair endpoints
# + health) and the WS upgrade path (`/ws/mac`, `/ws/phone`).
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

# Healthcheck so orchestrators know when the JS process is ready.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||3000)+'/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))"

# Run as a non-root uid Node prepared for us.
USER node

WORKDIR /app/apps/server
CMD ["node", "dist/index.js"]
