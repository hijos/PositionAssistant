FROM node:22-bookworm-slim

ENV NODE_ENV=production \
    QUOTA_HOST=0.0.0.0 \
    QUOTA_PORT=4100 \
    QUOTA_DB_PATH=/app/data/db.json \
    QUOTA_SEED_PATH=/app/seed.json

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY quota-service/index.js quota-service/fund-catalog.json /app/quota-service/
COPY quota-service/public /app/quota-service/public
COPY quota-service/container-entrypoint.sh /app/quota-service/container-entrypoint.sh
COPY quota-service/seed.json /app/seed.json

RUN mkdir -p /app/data \
  && chmod +x /app/quota-service/container-entrypoint.sh \
  && chown -R node:node /app

USER node

EXPOSE 4100

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:4100/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"

ENTRYPOINT ["/app/quota-service/container-entrypoint.sh"]
