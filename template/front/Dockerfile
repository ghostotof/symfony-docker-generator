ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-bookworm-slim AS base
RUN apt-get update && apt-get install -y --no-install-recommends curl git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /app

FROM base AS deps
COPY app/package.json app/package-lock.json* ./
RUN npm ci

FROM base AS dev
ENV NODE_ENV=development
COPY --from=deps /app/node_modules ./node_modules
EXPOSE 3000
CMD ["npm", "run", "dev"]

FROM base AS builder
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY app/ .
RUN npm run build

FROM base AS prod
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs \
    && adduser  --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
ENV PORT=3000 HOSTNAME=0.0.0.0
CMD ["node", "server.js"]
