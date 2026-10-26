# -----------------------------------------------------------------------------
# Étape 1 : Builder & Tests (Multi-stage)
# -----------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Copie des manifestes et installation des dépendances
COPY package*.json ./
RUN npm install

# Copie des sources
COPY . .

# Étape cible pour l'exécution des tests automatisés et du linter
FROM builder AS test

ENV NODE_ENV=development
RUN npm run lint && npm test

# -----------------------------------------------------------------------------
# Étape 2 : Image de Production Minimale & Sécurisée
# -----------------------------------------------------------------------------
FROM node:20-alpine AS production

# Arguments pour l'injection des métadonnées OCI
ARG APP_VERSION=dev
ARG GIT_SHA=unknown

# Labels Open Container Initiative (OCI)
LABEL org.opencontainers.image.authors="DevOps Team" \
      org.opencontainers.image.title="Shop API" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

WORKDIR /app

ENV NODE_ENV=production

# Installation stricte des dépendances de production uniquement
COPY package*.json ./
RUN npm install --only=production && npm cache clean --force

# Copie du code applicatif en attribuant la propriété à l'utilisateur node (1000)
COPY --chown=1000:1000 . .

# Bilan de santé de l'API (forme JSON exec notation pour satisfaire DL3025)
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/products', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]

# Utilisation de l'UID numérique 1000 au lieu du nom 'node' (satisfait DL3066)
USER 1000

EXPOSE 3000

# Forme exec recommandée
CMD ["node", "src/server.js"]