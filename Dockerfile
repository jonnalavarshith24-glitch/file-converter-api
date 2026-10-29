FROM node:20-bookworm-slim

# System Chromium for Markdown -> PDF rendering
RUN apt-get update \
 && apt-get install -y --no-install-recommends chromium fonts-liberation fonts-noto-color-emoji \
 && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    PUPPETEER_SKIP_DOWNLOAD=true \
    CHROMIUM_PATH=/usr/bin/chromium \
    CHROMIUM_NO_SANDBOX=true

WORKDIR /app

COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

COPY src ./src
RUN mkdir -p /app/storage && chown -R node:node /app

USER node
EXPOSE 3000
CMD ["node", "src/server.js"]
