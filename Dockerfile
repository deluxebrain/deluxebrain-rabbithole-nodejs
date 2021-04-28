ARG NODE_VERSION=14.16.1
ARG ALPINE_VERSION=3.13

FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS build
ARG APP_NAME
ARG VERSION

WORKDIR /tmp/package
ADD ${APP_NAME}-${VERSION}.tgz /tmp

RUN npm install ./ --only=production && \
  npm audit --audit-level=low

FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS release
ARG APP_NAME
ARG VERSION
ARG REVISION
ARG NOW

LABEL org.opencontainers.image.title=${APP_NAME} \
      org.opencontainers.image.version=${VERSION} \
      org.opencontainers.image.revision=${REVISION} \
      org.opencontainers.image.created=${NOW} \
      org.opencontainers.image.authors="deluxebrain <the@deluxebrain.com>" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://https://github.com/deluxebrain/foo" \
      org.opencontainers.image.url="https://deluxebrain.com" \
      org.opencontainers.image.vendor="deluxebrain"

WORKDIR /srv
COPY --from=build /tmp/package/ .

EXPOSE 3000
ENV HOST 0.0.0.0
ENV PORT 3000
USER node
CMD ["node", "./dist/server.js"]
