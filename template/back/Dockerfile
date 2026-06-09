# ═══════════════════════════════════════════════════════════
#  FrankenPHP — image officielle (embarque Caddy + PHP)
#  https://frankenphp.dev/docs/docker/
# ═══════════════════════════════════════════════════════════
ARG FRANKENPHP_VERSION=1

# ── Stage base ──────────────────────────────────────────
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php8.4-alpine AS base

LABEL maintainer="your-team@example.com"

# Outils système (install-php-extensions gère les dépendances de build/runtime des extensions)
RUN apk add --no-cache \
        bash \
        curl \
        git \
        unzip \
        acl

# Extensions PHP
RUN install-php-extensions \
        pdo_pgsql \
        intl \
        zip \
        opcache \
        xml \
        mbstring \
        apcu \
        amqp \
        opentelemetry

# Composer depuis image officielle
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Symfony CLI — installateur universel (compatible Alpine/musl)
RUN set -eux; \
    curl -1sLf https://get.symfony.com/cli/installer | bash; \
    SYMFONY_BIN=$(find /root -name symfony -maxdepth 4 -type f | head -n1); \
    install -m 0755 "$SYMFONY_BIN" /usr/local/bin/symfony; \
    rm -rf /root/.symfony*

WORKDIR /var/www/app

# ── Stage dev ───────────────────────────────────────────
FROM base AS dev

# Xdebug en dev
RUN install-php-extensions xdebug

COPY docker/php/xdebug.ini   $PHP_INI_DIR/conf.d/xdebug.ini
COPY docker/php/php-dev.ini  $PHP_INI_DIR/conf.d/app.ini
COPY docker/entrypoint-dev.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080 443 443/udp 2019

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]

# ── Stage prod ──────────────────────────────────────────
FROM base AS prod

COPY docker/php/php-prod.ini $PHP_INI_DIR/conf.d/app.ini

COPY app/ /var/www/app/

RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && php bin/console cache:warmup --env=prod \
    && setfacl -R -m u:www-data:rwX -m u:"$(whoami)":rwX var \
    || chmod -R 777 var

COPY docker/entrypoint-prod.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080 443 443/udp 2019

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
