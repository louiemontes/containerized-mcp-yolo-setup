FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY server.js ./
USER node
EXPOSE 8000
CMD ["node", "server.js"]