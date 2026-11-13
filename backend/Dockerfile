# Sirena HR API. Built on the server itself (the DGX is ARM64), so Prisma picks the right engine.
FROM node:24-bookworm-slim AS build
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund --ignore-scripts
COPY prisma ./prisma
RUN npx prisma generate
COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
# Dev dependencies stay: the Prisma CLI that runs migrations at start-up is one of them.
RUN npm run build

FROM node:24-bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/prisma ./prisma
COPY --chown=node:node package.json ./
USER node
# Apply pending migrations, then start. Migrations only ever add; a failed one stops the start.
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main"]
