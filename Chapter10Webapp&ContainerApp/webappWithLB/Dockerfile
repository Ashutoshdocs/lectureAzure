FROM node:20-alpine

ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app

# Install dependencies first for better layer caching
COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY server.js ./

# Run as the non-root "node" user that ships with the image
USER node

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "server.js"]
