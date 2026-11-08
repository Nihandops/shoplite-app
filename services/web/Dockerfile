# syntax=docker/dockerfile:1
# ---- stage 1: stamp the build version into the static site ----
FROM alpine:3.22 AS build
ARG APP_VERSION=dev
WORKDIR /site
COPY public/ ./
RUN sed -i "s/__APP_VERSION__/${APP_VERSION}/g" index.html

# ---- stage 2: unprivileged nginx (runs as uid 101, listens on 8080) ----
FROM nginxinc/nginx-unprivileged:1.29-alpine
ENV API_UPSTREAM=http://catalog-api:8000 \
    NGINX_ENVSUBST_FILTER=API_UPSTREAM
COPY --chown=101:101 nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build --chown=101:101 /site/ /usr/share/nginx/html/
USER 101
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
