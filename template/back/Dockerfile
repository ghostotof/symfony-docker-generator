# ═══════════════════════════════════════════════════════════
#  FrankenPHP — image officielle (embarque Caddy + PHP)
#  https://frankenphp.dev/docs/docker/
# ═══════════════════════════════════════════════════════════
ARG FRANKENPHP_VERSION=1.2

# ── Stage base ──────────────────────────────────────────
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php8.3-bookworm AS base

LABEL maintainer="your-team@example.com"

# Dépendances système
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        unzip \
        libpq-dev \
        libicu-dev \
        libzip-dev \
        libxml2-dev \
        libonig-dev \
        librabbitmq-dev \
        libssl-dev \
        acl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Symfony CLI
RUN curl -1sLf 'https://dl.cloudsmith.io/public/symfony/stable/setup.deb.sh' | bash \
    && apt-get install -y symfony-cli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

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
