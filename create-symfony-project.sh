#!/usr/bin/env bash
#
# =============================================================================
#  create-symfony-project.sh
# -----------------------------------------------------------------------------
#  Crée l'arborescence complète d'un projet Symfony dockerisé.
#
#  Services générés :
#    - backend   : PHP-FPM (Alpine) + symfony-cli + composer  -> code Symfony
#    - web       : nginx (Alpine), reverse proxy vers php-fpm
#    - database  : PostgreSQL (Alpine)
#    - rabbitmq  : RabbitMQ + plugin management (Alpine)
#    - frontend  : Node (Alpine) + Vite         [UNIQUEMENT avec --frontend]
#
#  Principe de versionnage :
#    Toutes les versions « stable latest » sont RÉSOLUES AU MOMENT DE
#    L'EXÉCUTION du script (API Docker Hub / GitHub / Packagist / PECL / npm)
#    puis FIGÉES EN DUR dans le fichier .env généré et dans versions.lock.
#    Le projet est donc parfaitement reproductible : deux exécutions à deux
#    dates différentes donnent deux projets aux versions différentes, mais
#    chaque projet reste stable dans le temps.
#
#  Gestion des droits (hôte Linux) :
#    L'UID/GID de l'utilisateur courant sont injectés en ARG de build. Un
#    utilisateur `dev` portant EXACTEMENT ces UID/GID est créé dans l'image,
#    et le pool php-fpm tourne sous cette identité. Les fichiers créés par le
#    conteneur (projet Symfony, cache, vendor/) appartiennent donc à l'utilisateur
#    hôte : ils sont directement lisibles ET éditables depuis l'IDE, sans avoir
#    besoin d'entrer dans le conteneur ni de faire de `chown` après coup.
#
#  Usage :
#    ./create-symfony-project.sh <nom-du-projet> [options]
#
#  Options :
#    --frontend        Ajoute un service `frontend` dédié (Node + Vite).
#                      Dans ce mode, le backend est généré en Symfony *minimal*
#                      + API Platform (mode API pur). Sans cette option, le
#                      backend est un Symfony *full* (--webapp) qui gère le front
#                      lui-même (Twig, AssetMapper, etc.).
#    --path <dir>      Répertoire parent dans lequel créer le projet (défaut : .)
#    --no-build        Génère uniquement les fichiers, sans build ni init Docker.
#    -h, --help        Affiche cette aide.
#
#  Prérequis : bash 4+, curl, jq, docker (avec le plugin compose v2), git
# =============================================================================

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# 1. Helpers d'affichage
# -----------------------------------------------------------------------------
# Couleurs ANSI, désactivées automatiquement si la sortie n'est pas un terminal
# (utile quand le script est redirigé vers un fichier de log).
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'
  C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""
fi

info() { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()   { printf '%s ✔ %s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s ⚠ %s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err()  { printf '%s ✘ %s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# Trap global : si une commande échoue (set -e), on indique la ligne fautive.
trap 'err "Échec ligne $LINENO. Le script est interrompu."' ERR

# -----------------------------------------------------------------------------
# 2. Parsing des arguments
# -----------------------------------------------------------------------------
PROJECT_NAME=""      # Argument obligatoire
WITH_FRONTEND=0      # 0 = backend full-stack ; 1 = service frontend dédié
TARGET_PARENT="."    # Répertoire parent où sera créé le dossier projet
DO_BUILD=1           # 1 = build + init des conteneurs à la fin

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --frontend)  WITH_FRONTEND=1; shift ;;
    --path)      TARGET_PARENT="${2:?--path attend un répertoire}"; shift 2 ;;
    --no-build)  DO_BUILD=0; shift ;;
    -h|--help)   usage ;;
    -*)          die "Option inconnue : $1 (voir --help)" ;;
    *)
      # Le premier argument positionnel est le nom du projet ; un second est une erreur.
      [[ -z "$PROJECT_NAME" ]] || die "Un seul nom de projet est attendu."
      PROJECT_NAME="$1"; shift ;;
  esac
done

# Le nom du projet est OBLIGATOIRE.
[[ -n "$PROJECT_NAME" ]] || die "Nom du projet manquant. Usage : $(basename "$0") <nom-du-projet> [--frontend]"

# On contraint le nom : il sert de nom de dossier, de préfixe de conteneurs
# Docker et de nom de base de données. Docker Compose n'accepte que
# [a-z0-9_-] pour les noms de projet.
[[ "$PROJECT_NAME" =~ ^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$ ]] \
  || die "Nom invalide : '$PROJECT_NAME'. Attendu : minuscules, chiffres, '-' et '_' (doit commencer/finir par un alphanumérique)."

PROJECT_DIR="${TARGET_PARENT%/}/${PROJECT_NAME}"
[[ ! -e "$PROJECT_DIR" ]] || die "'$PROJECT_DIR' existe déjà. Choisissez un autre nom ou supprimez-le."

# -----------------------------------------------------------------------------
# 3. Vérification des prérequis
# -----------------------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Commande requise absente : $1"; }
need curl; need jq; need git; need sed; need awk
if (( DO_BUILD )); then
  need docker
  docker compose version >/dev/null 2>&1 \
    || die "Le plugin 'docker compose' (v2) est requis. (docker-compose v1 n'est pas supporté.)"
fi

# UID/GID de l'utilisateur hôte : c'est LA clé de la gestion des droits.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
[[ "$HOST_UID" != "0" ]] || warn "Vous exécutez le script en root : les fichiers appartiendront à root."

# -----------------------------------------------------------------------------
# 4. Résolution des versions « stable latest »
# -----------------------------------------------------------------------------
# Chaque fonction interroge une API publique et renvoie une version exacte.
# En cas d'échec réseau, on retombe sur une valeur de secours (fallback) afin
# que le script reste utilisable hors ligne — un avertissement est alors affiché.

# Récupère jusqu'à 3 pages de tags Docker Hub pour un dépôt donné.
#   $1 = dépôt (ex: library/php)   $2 = filtre de nom (ex: fpm-alpine)
dockerhub_tags() {
  local repo="$1" filter="$2" page
  for page in 1 2 3; do
    curl -fsSL --max-time 15 \
      "https://hub.docker.com/v2/repositories/${repo}/tags/?page_size=100&page=${page}&name=${filter}" \
      2>/dev/null | jq -r '.results[]?.name' || true
  done
}

# Filtre une liste de tags (stdin) via une regex et renvoie la version la plus
# haute. `sort -V` = tri « version », qui comprend que 8.4.10 > 8.4.9.
pick_highest() { { grep -E "$1" || true; } | sort -V | tail -n1; }

# Résout un tag Docker Hub avec fallback.
#   $1 label  $2 dépôt  $3 filtre  $4 regex  $5 fallback
resolve_docker_tag() {
  local label="$1" out
  out="$(dockerhub_tags "$2" "$3" | pick_highest "$4")"
  if [[ -z "$out" ]]; then
    warn "Résolution de '$label' impossible → fallback : $5"
    out="$5"
  fi
  printf '%s' "$out"
}

# Dernière release GitHub (tag_name, sans le 'v' initial).
resolve_github_release() {
  local label="$1" repo="$2" fallback="$3" out
  out="$(curl -fsSL --max-time 15 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' | sed 's/^v//')"
  [[ -n "$out" ]] || { warn "Résolution de '$label' impossible → fallback : $fallback"; out="$fallback"; }
  printf '%s' "$out"
}

# Dernière version stable d'un paquet Composer (métadonnées Packagist v2).
# On exclut volontairement les alpha/beta/RC via la regex.
resolve_packagist() {
  local label="$1" pkg="$2" fallback="$3" out
  out="$(curl -fsSL --max-time 15 "https://repo.packagist.org/p2/${pkg}.json" 2>/dev/null \
        | jq -r '.packages[][]?.version' \
        | { grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sed 's/^v//' | sort -V | tail -n1)"
  [[ -n "$out" ]] || { warn "Résolution de '$label' impossible → fallback : $fallback"; out="$fallback"; }
  printf '%s' "$out"
}

# Dernière version stable d'une extension PECL.
resolve_pecl() {
  local label="$1" ext="$2" fallback="$3" out
  out="$(curl -fsSL --max-time 15 "https://pecl.php.net/rest/r/${ext}/stable.txt" 2>/dev/null | tr -d '[:space:]')"
  [[ "$out" =~ ^[0-9] ]] || { warn "Résolution de '$label' impossible → fallback : $fallback"; out="$fallback"; }
  printf '%s' "$out"
}

# Dernière version publiée d'un paquet npm (tag 'latest').
resolve_npm() {
  local label="$1" pkg="$2" fallback="$3" out
  out="$(curl -fsSL --max-time 15 "https://registry.npmjs.org/${pkg}/latest" 2>/dev/null | jq -r '.version // empty')"
  [[ -n "$out" ]] || { warn "Résolution de '$label' impossible → fallback : $fallback"; out="$fallback"; }
  printf '%s' "$out"
}

info "Résolution des versions stables (cela prend quelques secondes)…"

# --- Images Docker -----------------------------------------------------------
# PHP : on veut la variante FPM Alpine (nginx + php-fpm). Regex volontairement
# stricte pour écarter les tags RC/beta (ex: 8.5.0RC1-fpm-alpine3.22).
PHP_TAG="$(resolve_docker_tag "php-fpm-alpine" "library/php" "fpm-alpine" \
           '^[0-9]+\.[0-9]+\.[0-9]+-fpm-alpine[0-9.]*$' "8.4.11-fpm-alpine3.22")"

# nginx : la branche STABLE correspond aux versions à mineur PAIR (1.28, 1.26…),
# la branche mainline aux mineurs impairs (1.29…). On ne garde donc que les pairs.
NGINX_TAG="$(dockerhub_tags "library/nginx" "alpine" \
             | { grep -E '^[0-9]+\.[0-9]+\.[0-9]+-alpine$' || true; } \
             | awk -F'[.-]' '$2 % 2 == 0' | sort -V | tail -n1)"
[[ -n "$NGINX_TAG" ]] || { warn "Résolution de 'nginx' impossible → fallback : 1.28.0-alpine"; NGINX_TAG="1.28.0-alpine"; }

# PostgreSQL : versionnage majeur.mineur (ex: 17.5-alpine).
POSTGRES_TAG="$(resolve_docker_tag "postgres-alpine" "library/postgres" "alpine" \
                '^[0-9]+\.[0-9]+-alpine$' "17.5-alpine")"

# RabbitMQ : variante '-management-alpine' pour disposer de l'UI web (port 15672).
RABBITMQ_TAG="$(resolve_docker_tag "rabbitmq-management-alpine" "library/rabbitmq" "management-alpine" \
                '^[0-9]+\.[0-9]+\.[0-9]+-management-alpine$' "4.1.0-management-alpine")"

# Composer : SEULE EXCEPTION à la règle du figeage exact.
# On résout d'abord la dernière version stable (à titre informatif, tracée dans
# versions.lock), puis on n'épingle que la BRANCHE MAJEURE (ex: `composer:2`).
# Compromis assumé :
#   - on récupère automatiquement les correctifs 2.x au fil des rebuilds,
#     Composer étant un outil de build et non une dépendance applicative ;
#   - un futur Composer 3 (changement majeur, donc potentiellement cassant)
#     ne viendra jamais casser le build sans action explicite du développeur.
COMPOSER_RESOLVED="$(resolve_docker_tag "composer" "library/composer" "2." \
                     '^[0-9]+\.[0-9]+\.[0-9]+$' "2.8.9")"
# Extraction du numéro majeur : "2.8.9" -> "2"
COMPOSER_TAG="${COMPOSER_RESOLVED%%.*}"

# Node : versions LTS = majeur PAIR. On écarte donc les majeurs impairs (Current).
NODE_TAG=""
if (( WITH_FRONTEND )); then
  NODE_TAG="$(dockerhub_tags "library/node" "alpine" \
              | { grep -E '^[0-9]+\.[0-9]+\.[0-9]+-alpine[0-9.]*$' || true; } \
              | awk -F'.' '$1 % 2 == 0' | sort -V | tail -n1)"
  [[ -n "$NODE_TAG" ]] || { warn "Résolution de 'node' impossible → fallback : 22.14.0-alpine"; NODE_TAG="22.14.0-alpine"; }
fi

# --- Outils et paquets -------------------------------------------------------
SYMFONY_CLI_VERSION="$(resolve_github_release "symfony-cli" "symfony-cli/symfony-cli" "5.14.0")"
AMQP_EXT_VERSION="$(resolve_pecl "ext-amqp" "amqp" "2.1.2")"
# Xdebug n'est utilisé que par le stage `preprod` (profilage à la demande).
XDEBUG_VERSION="$(resolve_pecl "ext-xdebug" "xdebug" "3.4.1")"
SYMFONY_VERSION="$(resolve_packagist "symfony/skeleton" "symfony/skeleton" "7.3.0")"

API_PLATFORM_VERSION=""
CREATE_VITE_VERSION=""
if (( WITH_FRONTEND )); then
  API_PLATFORM_VERSION="$(resolve_packagist "api-platform/symfony" "api-platform/symfony" "4.1.0")"
  CREATE_VITE_VERSION="$(resolve_npm "create-vite" "create-vite" "7.0.0")"
fi

# Récapitulatif à l'écran : le dev voit exactement ce qui va être figé.
printf '\n%s--- Versions figées pour ce projet ---%s\n' "$C_DIM" "$C_RESET"
printf '  php            : %s\n' "$PHP_TAG"
printf '  nginx          : %s\n' "$NGINX_TAG"
printf '  postgres       : %s\n' "$POSTGRES_TAG"
printf '  rabbitmq       : %s\n' "$RABBITMQ_TAG"
printf '  composer       : %s  %s(branche majeure — %s au moment de la génération)%s\n' \
       "$COMPOSER_TAG" "$C_DIM" "$COMPOSER_RESOLVED" "$C_RESET"
printf '  symfony-cli    : %s\n' "$SYMFONY_CLI_VERSION"
printf '  ext-amqp       : %s\n' "$AMQP_EXT_VERSION"
printf '  ext-xdebug     : %s  %s(stage preprod)%s\n' "$XDEBUG_VERSION" "$C_DIM" "$C_RESET"
printf '  symfony        : %s\n' "$SYMFONY_VERSION"
(( WITH_FRONTEND )) && {
printf '  api-platform   : %s\n' "$API_PLATFORM_VERSION"
printf '  node           : %s\n' "$NODE_TAG"
printf '  create-vite    : %s\n' "$CREATE_VITE_VERSION"
}
printf '\n'

# -----------------------------------------------------------------------------
# 5. Création de l'arborescence
# -----------------------------------------------------------------------------
info "Création de l'arborescence dans '$PROJECT_DIR'…"
mkdir -p "$PROJECT_DIR"/{backend,docker/php,docker/nginx}
(( WITH_FRONTEND )) && mkdir -p "$PROJECT_DIR/frontend" "$PROJECT_DIR/docker/node"
cd "$PROJECT_DIR"

# -----------------------------------------------------------------------------
# 5.1 .env — TOUTES les versions figées + paramètres locaux
# -----------------------------------------------------------------------------
# Heredoc NON quoté (<<EOF) : les variables du script sont interpolées ici,
# ce qui « grave » les versions résolues dans le fichier.
cat > .env <<EOF
# =============================================================================
# Variables d'environnement Docker Compose
# Généré le $(date -Iseconds) par create-symfony-project.sh
# Les versions ci-dessous sont FIGÉES : ne les modifiez qu'en connaissance de cause.
# =============================================================================

COMPOSE_PROJECT_NAME=${PROJECT_NAME}

# --- Identité de l'utilisateur hôte ------------------------------------------
# Injectés en ARG de build pour créer un utilisateur 'dev' aux mêmes UID/GID.
# C'est ce qui permet d'éditer directement les fichiers depuis l'IDE.
UID=${HOST_UID}
GID=${HOST_GID}

# --- Versions des images (figées) --------------------------------------------
PHP_TAG=${PHP_TAG}
NGINX_TAG=${NGINX_TAG}
POSTGRES_TAG=${POSTGRES_TAG}
RABBITMQ_TAG=${RABBITMQ_TAG}
NODE_TAG=${NODE_TAG}

# Composer : épinglé sur la BRANCHE MAJEURE uniquement (exception assumée).
# Les correctifs 2.x sont récupérés à chaque rebuild ; un Composer 3 ne sera
# jamais installé sans modification explicite de cette ligne.
# Version disponible au moment de la génération : ${COMPOSER_RESOLVED}
# Pour figer complètement : COMPOSER_TAG=${COMPOSER_RESOLVED}
COMPOSER_TAG=${COMPOSER_TAG}

# --- Versions des outils / paquets (figées) ----------------------------------
SYMFONY_CLI_VERSION=${SYMFONY_CLI_VERSION}
AMQP_EXT_VERSION=${AMQP_EXT_VERSION}
XDEBUG_VERSION=${XDEBUG_VERSION}
SYMFONY_VERSION=${SYMFONY_VERSION}
API_PLATFORM_VERSION=${API_PLATFORM_VERSION}
CREATE_VITE_VERSION=${CREATE_VITE_VERSION}

# --- Mode de génération du backend -------------------------------------------
# full = Symfony --webapp (Twig, AssetMapper : le backend gère le front)
# api  = Symfony minimal + API Platform (front délégué au service 'frontend')
BACKEND_FLAVOR=$( (( WITH_FRONTEND )) && echo api || echo full )

# --- Ports exposés sur l'hôte ------------------------------------------------
HTTP_PORT=8080
POSTGRES_PORT=5432
RABBITMQ_PORT=5672
RABBITMQ_UI_PORT=15672
VITE_PORT=5173

# --- Base de données ---------------------------------------------------------
POSTGRES_DB=${PROJECT_NAME//-/_}
POSTGRES_USER=app
POSTGRES_PASSWORD=app

# --- RabbitMQ ----------------------------------------------------------------
RABBITMQ_USER=app
RABBITMQ_PASSWORD=app
EOF

# Copie lisible du récapitulatif de versions (pratique en revue de code / CI).
cat > versions.lock <<EOF
# Versions résolues le $(date -Iseconds)
php=${PHP_TAG}
nginx=${NGINX_TAG}
postgres=${POSTGRES_TAG}
rabbitmq=${RABBITMQ_TAG}
composer=${COMPOSER_TAG}
# Composer n'est pas figé exactement : seule la branche majeure est épinglée.
# Version disponible à la génération (pour référence) :
composer-resolved=${COMPOSER_RESOLVED}
symfony-cli=${SYMFONY_CLI_VERSION}
ext-amqp=${AMQP_EXT_VERSION}
ext-xdebug=${XDEBUG_VERSION}
symfony=${SYMFONY_VERSION}
api-platform=${API_PLATFORM_VERSION}
node=${NODE_TAG}
create-vite=${CREATE_VITE_VERSION}
EOF

# -----------------------------------------------------------------------------
# 5.2 docker/php/Dockerfile
# -----------------------------------------------------------------------------
# Heredoc QUOTÉ (<<'EOF') : rien n'est interpolé par bash. Les ${...} présents
# sont des ARG Docker, résolus au moment du build à partir du .env.
cat > docker/php/Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
# =============================================================================
# Image applicative PHP-FPM — multi-stage
# -----------------------------------------------------------------------------
#  Cibles disponibles (--target) :
#
#    dev         Poste de développement. Code monté en bind mount, symfony-cli,
#                UID/GID alignés sur l'hôte, opcache en revalidation immédiate.
#
#    production  Artefact déployable. Le code est COPIÉ dans l'image (aucun
#                montage), dépendances de dev exclues, opcache verrouillé +
#                preloading, exécution en utilisateur non-root fixe.
#
#    preprod     CONSTRUIT À PARTIR DE `production`. C'est volontaire : la
#                préprod doit valider l'artefact réellement déployé, pas un
#                artefact cousin. On n'ajoute qu'un delta d'observabilité
#                (Xdebug en mode profilage, logs verbeux). Le déclarer après
#                `production` dans le fichier est une contrainte Docker, pas
#                un ordre de pipeline : celui-ci reste dev → preprod → prod.
#
#  Le contexte de build est la RACINE DU PROJET (et non docker/php), car les
#  stages de déploiement doivent pouvoir copier ./backend. Voir .dockerignore.
# =============================================================================

ARG PHP_TAG
ARG COMPOSER_TAG

# -----------------------------------------------------------------------------
# Stage : composer_bin — binaire Composer issu de l'image officielle
# -----------------------------------------------------------------------------
FROM composer:${COMPOSER_TAG} AS composer_bin

# =============================================================================
# Stage : base — socle commun à TOUTES les cibles
# Contient PHP, ses extensions et les librairies runtime. Rien de spécifique
# à un environnement : c'est ce qui garantit que dev et prod partagent le même
# moteur PHP et les mêmes versions d'extensions.
# =============================================================================
FROM php:${PHP_TAG} AS base

ARG AMQP_EXT_VERSION

RUN set -eux; \
    apk add --no-cache \
        icu-libs libpq libzip rabbitmq-c tzdata \
        fcgi; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS icu-dev postgresql-dev libzip-dev rabbitmq-c-dev linux-headers; \
    # Extensions requises par Symfony / Doctrine / Messenger
    #   intl      : traductions, formats de dates et de nombres
    #   pdo_pgsql : driver PostgreSQL pour Doctrine
    #   zip       : requis par Composer pour les archives
    #   opcache   : cache d'opcodes (réglages différents selon la cible)
    #   sockets   : dépendance de plusieurs transports Messenger
    docker-php-ext-install -j"$(nproc)" intl pdo_pgsql zip opcache sockets; \
    # amqp : transport RabbitMQ natif pour Messenger
    pecl install "amqp-${AMQP_EXT_VERSION}"; \
    docker-php-ext-enable amqp; \
    apk del --no-network .build-deps; \
    rm -rf /tmp/pear

COPY --from=composer_bin /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www/backend

# =============================================================================
# Stage : dev — environnement de développement local
# =============================================================================
FROM base AS dev

ARG UID=1000
ARG GID=1000
ARG SYMFONY_CLI_VERSION

# Outils confort, inutiles (et indésirables) dans une image déployée.
RUN apk add --no-cache bash git curl unzip

# --- symfony-cli --------------------------------------------------------------
# Binaire distribué par architecture : on détecte celle de l'hôte pour supporter
# aussi bien x86_64 que arm64 (Apple Silicon, Ampere…).
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  ARCH=amd64 ;; \
        aarch64) ARCH=arm64 ;; \
        *) echo "Architecture non supportée : $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/symfony-cli.tar.gz \
        "https://github.com/symfony-cli/symfony-cli/releases/download/v${SYMFONY_CLI_VERSION}/symfony-cli_linux_${ARCH}.tar.gz"; \
    tar -xzf /tmp/symfony-cli.tar.gz -C /usr/local/bin symfony; \
    chmod +x /usr/local/bin/symfony; \
    rm -f /tmp/symfony-cli.tar.gz; \
    symfony version

# -----------------------------------------------------------------------------
# Utilisateur `dev` aligné sur l'UID/GID de l'hôte
# -----------------------------------------------------------------------------
# Cœur de la gestion des droits : tout fichier écrit par le conteneur (vendor/,
# var/cache, code généré par le maker…) appartient à l'utilisateur hôte. Aucun
# `sudo chown` n'est nécessaire côté IDE.
# Les tests `getent` gèrent le cas où l'UID/GID existe déjà dans l'image de base.
RUN set -eux; \
    if ! getent group "${GID}" >/dev/null; then addgroup -g "${GID}" dev; fi; \
    GROUP_NAME="$(getent group "${GID}" | cut -d: -f1)"; \
    if ! getent passwd "${UID}" >/dev/null; then \
        adduser -u "${UID}" -G "${GROUP_NAME}" -s /bin/bash -D dev; \
    fi; \
    USER_NAME="$(getent passwd "${UID}" | cut -d: -f1)"; \
    mkdir -p /var/www/backend "/home/${USER_NAME}/.composer" "/home/${USER_NAME}/.symfony5"; \
    chown -R "${UID}:${GID}" /var/www "/home/${USER_NAME}"

COPY docker/php/php.dev.ini  /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/php/www.dev.conf /usr/local/etc/php-fpm.d/zz-www.conf

COPY docker/php/init-symfony.sh /usr/local/bin/init-symfony
RUN chmod +x /usr/local/bin/init-symfony

# Le master php-fpm tourne en root (nécessaire pour ouvrir le socket et basculer
# d'identité) ; les workers tournent en `dev` (voir www.dev.conf).
EXPOSE 9000
CMD ["php-fpm", "-F"]

# =============================================================================
# Stage : vendor — résolution des dépendances PHP de production
# Isolé pour tirer parti du cache Docker : tant que composer.json/lock ne
# changent pas, cette couche coûteuse n'est pas rejouée.
# =============================================================================
FROM base AS vendor

ENV COMPOSER_ALLOW_SUPERUSER=1

# On copie d'abord UNIQUEMENT les manifestes : modifier du code applicatif
# n'invalide donc pas le cache de `composer install`.
COPY backend/composer.json backend/composer.lock ./

# --no-dev            : exclut phpunit, maker-bundle, debug-pack…
# --optimize-autoloader + --classmap-authoritative : autoloader statique, sans
#                       accès disque à l'exécution (gain net en production).
# --no-scripts        : les scripts Symfony ont besoin du code source, qui
#                       n'est pas encore présent ; ils sont rejoués plus bas.
RUN composer install \
        --no-dev \
        --no-scripts \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader \
        --classmap-authoritative

# =============================================================================
# Stage : production — artefact déployable
# =============================================================================
FROM base AS production

ARG BACKEND_FLAVOR=full

# UID fixe et arbitraire (hors plage système). Aucun alignement avec un hôte
# n'est nécessaire ici : il n'y a plus de bind mount. Un UID numérique explicite
# est par ailleurs requis par `runAsNonRoot` côté Kubernetes.
ARG APP_UID=10001
ARG APP_GID=10001

ENV APP_ENV=prod \
    APP_DEBUG=0 \
    COMPOSER_ALLOW_SUPERUSER=1

RUN set -eux; \
    addgroup -g "${APP_GID}" app; \
    adduser -u "${APP_UID}" -G app -s /sbin/nologin -D app

# Dépendances puis code source : l'ordre importe pour le cache de couches.
COPY --from=vendor --chown=${APP_UID}:${APP_GID} /var/www/backend/vendor ./vendor
COPY --chown=${APP_UID}:${APP_GID} backend/ ./

RUN set -eux; \
    # Les scripts sautés au stage `vendor` sont rejoués maintenant que le code
    # est présent (génération de .env.local.php, cache warmup…).
    composer dump-autoload --no-dev --classmap-authoritative; \
    composer run-script --no-dev post-install-cmd || true; \
    # Compilation des assets : uniquement en mode full-stack (AssetMapper).
    # En mode API, il n'y a aucun asset à compiler.
    if [ "${BACKEND_FLAVOR}" = "full" ]; then \
        php bin/console asset-map:compile --no-interaction; \
    fi; \
    # var/ doit rester inscriptible : c'est le SEUL chemin mutable de l'image.
    # Le reste peut tourner en système de fichiers read-only.
    mkdir -p var/cache var/log; \
    chown -R "${APP_UID}:${APP_GID}" var; \
    # Nettoyage : ni Composer ni les manifestes n'ont d'utilité à l'exécution.
    rm -f /usr/local/bin/composer

COPY docker/php/php.prod.ini  /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/php/www.prod.conf /usr/local/etc/php-fpm.d/zz-www.conf

# Sonde utilisée par les readiness/liveness probes Kubernetes.
COPY docker/php/healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x /usr/local/bin/healthcheck

# Exécution non-root de bout en bout : le master php-fpm lui-même tourne en
# `app`, ce qui permet un `runAsNonRoot: true` et un `readOnlyRootFilesystem`.
USER app

EXPOSE 9000
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]
CMD ["php-fpm", "-F"]

# =============================================================================
# Stage : preprod — production + delta d'observabilité
# -----------------------------------------------------------------------------
# `FROM production` est le point clé : les couches applicatives sont
# BIT À BIT IDENTIQUES à celles de l'image de production. Ce que l'on valide en
# préprod est donc bien l'artefact qui sera déployé, augmenté d'outils de
# diagnostic — et non une seconde compilation qui pourrait diverger.
# =============================================================================
FROM production AS preprod

ARG XDEBUG_VERSION

# L'installation d'extensions requiert root ; on repasse en `app` à la fin.
USER root

RUN set -eux; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS linux-headers; \
    pecl install "xdebug-${XDEBUG_VERSION}"; \
    docker-php-ext-enable xdebug; \
    apk del --no-network .build-deps; \
    rm -rf /tmp/pear

# Xdebug en mode `profile`/`trace` uniquement, jamais `debug` : on mesure sans
# ouvrir de port d'attachement sur un environnement partagé.
# Le déclenchement est manuel (XDEBUG_TRIGGER), donc sans coût quand inutilisé.
COPY docker/php/xdebug.preprod.ini /usr/local/etc/php/conf.d/zz-xdebug.ini

# APP_DEBUG reste à 0 : la préprod doit se comporter comme la production.
# Seule la verbosité des logs est augmentée pour faciliter le diagnostic.
ENV APP_ENV=prod \
    APP_DEBUG=0 \
    LOG_LEVEL=debug

RUN mkdir -p /var/www/backend/var/profiler \
 && chown -R app:app /var/www/backend/var

USER app
CMD ["php-fpm", "-F"]
EOF

# -----------------------------------------------------------------------------
# 5.3 docker/php/php.dev.ini — réglages orientés développement
# -----------------------------------------------------------------------------
cat > docker/php/php.dev.ini <<'EOF'
; Réglages PHP pour l'environnement de développement
memory_limit = 512M
max_execution_time = 60
date.timezone = Europe/Paris

; OPcache activé mais avec revalidation immédiate : les modifications de code
; sont prises en compte sans redémarrer php-fpm (indispensable en dev).
opcache.enable = 1
opcache.enable_cli = 1
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0

; Affichage complet des erreurs en dev
display_errors = On
display_startup_errors = On
error_reporting = E_ALL

; Confort pour les imports de fixtures / uploads
upload_max_filesize = 32M
post_max_size = 32M
EOF

# -----------------------------------------------------------------------------
# 5.4 docker/php/www.dev.conf — pool php-fpm exécuté sous l'identité `dev`
# -----------------------------------------------------------------------------
# Note : `user`/`group` valent ici le NOM de l'utilisateur créé au build (aligné
# sur l'UID/GID hôte). C'est ce qui garantit que les fichiers écrits en runtime
# (var/cache, var/log, uploads) restent éditables depuis l'IDE.
cat > docker/php/www.dev.conf <<'EOF'
[www]
user = dev
group = dev

; Écoute TCP plutôt qu'un socket Unix : nginx est dans un autre conteneur.
listen = 0.0.0.0:9000

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

; Les logs des workers sont renvoyés vers la sortie standard du conteneur,
; donc visibles via `docker compose logs backend`.
catch_workers_output = yes
decorate_workers_output = no
clear_env = no
EOF

# -----------------------------------------------------------------------------
# 5.4b docker/php/php.prod.ini — réglages production (hérités par la préprod)
# -----------------------------------------------------------------------------
cat > docker/php/php.prod.ini <<'EOF'
; Réglages PHP pour les environnements déployés (production ET préprod).
memory_limit = 256M
max_execution_time = 30
date.timezone = Europe/Paris

; OPcache verrouillé : le code ne change jamais au sein d'une image, la
; revalidation sur disque est donc du gaspillage pur.
opcache.enable = 1
opcache.enable_cli = 0
opcache.validate_timestamps = 0
opcache.memory_consumption = 256
opcache.max_accelerated_files = 20000
opcache.interned_strings_buffer = 16

; Preloading : Symfony génère config/preload.php, qui charge le conteneur DI et
; les classes du framework une seule fois au démarrage du master php-fpm.
; Si le fichier est absent, PHP émet un avertissement au démarrage sans planter.
opcache.preload = /var/www/backend/config/preload.php
opcache.preload_user = app

; Aucune erreur ne doit fuiter vers le client : tout part dans les logs, qui
; sont récupérés par la sortie standard du conteneur.
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /proc/self/fd/2
error_reporting = E_ALL & ~E_DEPRECATED

expose_php = Off
upload_max_filesize = 16M
post_max_size = 16M

; Sessions en mémoire partagée uniquement si nécessaire ; par défaut on
; privilégie des jetons sans état (JWT) ou un stockage externe.
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
EOF

# -----------------------------------------------------------------------------
# 5.4c docker/php/www.prod.conf — pool php-fpm des environnements déployés
# -----------------------------------------------------------------------------
cat > docker/php/www.prod.conf <<'EOF'
[global]
; Le master lui-même tourne en `app` : aucun processus root dans le conteneur,
; ce qui permet `runAsNonRoot: true` côté Kubernetes.
error_log = /proc/self/fd/2
daemonize = no

[www]
user = app
group = app

listen = 0.0.0.0:9000

; `static` plutôt que `dynamic` : en conteneur, la mise à l'échelle se fait en
; ajoutant des pods, pas des workers. Un nombre fixe rend la consommation
; mémoire prévisible, ce qui est indispensable pour calibrer les limits.
pm = static
pm.max_children = 8
pm.max_requests = 500

; Statut interne, consommé par la sonde de santé et le scraping Prometheus.
pm.status_path = /-/fpm-status
ping.path = /-/fpm-ping
ping.response = pong

catch_workers_output = yes
decorate_workers_output = no
clear_env = no

; Les variables sensibles proviennent de l'orchestrateur (Secret Kubernetes),
; jamais de l'image. On les laisse simplement traverser.
env[APP_ENV] = $APP_ENV
env[DATABASE_URL] = $DATABASE_URL
env[MESSENGER_TRANSPORT_DSN] = $MESSENGER_TRANSPORT_DSN
EOF

# -----------------------------------------------------------------------------
# 5.4d docker/php/xdebug.preprod.ini — profilage à la demande en préprod
# -----------------------------------------------------------------------------
cat > docker/php/xdebug.preprod.ini <<'EOF'
; Xdebug en PRÉPRODUCTION uniquement.
;
; Mode `profile` + `trace` — jamais `debug` : on ne veut pas ouvrir de port
; d'attachement sur un environnement partagé et accessible.
xdebug.mode = profile,trace

; Déclenchement MANUEL : rien n'est profilé tant que la requête ne porte pas
; le déclencheur (en-tête, cookie ou paramètre XDEBUG_TRIGGER). Le surcoût est
; donc nul sur le trafic normal, ce qui rend les mesures de perf exploitables.
xdebug.start_with_request = trigger
xdebug.trigger_value = ${XDEBUG_TRIGGER_SECRET}

xdebug.output_dir = /var/www/backend/var/profiler
xdebug.profiler_output_name = cachegrind.out.%t.%p
xdebug.use_compression = 0
EOF

# -----------------------------------------------------------------------------
# 5.4e docker/php/healthcheck.sh — sonde de vivacité php-fpm
# -----------------------------------------------------------------------------
# Utilisé par HEALTHCHECK (Docker) et par les probes liveness/readiness
# (Kubernetes). On interroge le ping interne de php-fpm via FastCGI, ce qui
# valide réellement le pool — contrairement à un simple test de port ouvert.
cat > docker/php/healthcheck.sh <<'EOF'
#!/bin/sh
set -eu
SCRIPT_NAME=/-/fpm-ping \
SCRIPT_FILENAME=/-/fpm-ping \
REQUEST_METHOD=GET \
cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null | grep -q pong
EOF

# -----------------------------------------------------------------------------
# 5.4f .dockerignore — indispensable depuis que le contexte est la racine
# -----------------------------------------------------------------------------
# Sans ce fichier, chaque build enverrait vendor/, var/ et node_modules au
# démon Docker (plusieurs centaines de Mo) et invaliderait le cache en
# permanence. Il évite aussi de faire fuiter .env.local dans l'image.
cat > .dockerignore <<'EOF'
.git
.gitignore
.env.local
.env.*.local
*.md
Makefile
versions.lock

backend/vendor/
backend/var/
backend/.env.local
backend/public/assets/
backend/public/bundles/

frontend/node_modules/
frontend/dist/

k8s/
.idea/
.vscode/
EOF

# -----------------------------------------------------------------------------
# 5.5 docker/php/init-symfony.sh — création du projet Symfony
# -----------------------------------------------------------------------------
# Ce script est embarqué dans l'image et exécuté UNE FOIS, en tant que `dev`,
# via : docker compose run --rm --user dev backend init-symfony
cat > docker/php/init-symfony.sh <<'EOF'
#!/usr/bin/env bash
# =============================================================================
# Initialise le projet Symfony dans /var/www/backend (monté depuis l'hôte).
# Idempotent : si composer.json existe déjà, le script ne fait rien.
# =============================================================================
set -Eeuo pipefail

APP_DIR="/var/www/backend"
cd "$APP_DIR"

if [[ -f composer.json ]]; then
  echo "→ Projet Symfony déjà initialisé, rien à faire."
  exit 0
fi

: "${SYMFONY_VERSION:?SYMFONY_VERSION doit être défini}"
: "${BACKEND_FLAVOR:=full}"

echo "→ Création d'un projet Symfony ${SYMFONY_VERSION} (mode : ${BACKEND_FLAVOR})"

# `symfony new` exige un répertoire cible vide et le crée lui-même. On passe par
# un dossier temporaire puis on déplace le contenu, ce qui évite tout conflit
# avec le point de montage (et les éventuels fichiers déjà présents).
TMP_DIR="$(mktemp -d)"
rmdir "$TMP_DIR"

NEW_ARGS=( "$TMP_DIR" "--version=${SYMFONY_VERSION}" "--no-git" )
# --webapp installe le pack complet (Twig, AssetMapper, formulaires, sécurité…).
# Sans ce flag on obtient le squelette minimal, base idéale d'une API.
[[ "$BACKEND_FLAVOR" == "full" ]] && NEW_ARGS+=( "--webapp" )

symfony new "${NEW_ARGS[@]}"

# Déplacement du contenu, fichiers cachés compris (.env, .gitignore…).
shopt -s dotglob
mv "$TMP_DIR"/* "$APP_DIR"/
shopt -u dotglob
rmdir "$TMP_DIR"

if [[ "$BACKEND_FLAVOR" == "api" ]]; then
  echo "→ Installation d'API Platform ${API_PLATFORM_VERSION} + strict nécessaire (BDD, Messenger)"
  # Version exacte figée : on garde la maîtrise du numéro installé.
  composer require --no-interaction "api-platform/symfony:${API_PLATFORM_VERSION}"
  # api-platform/symfony n'embarque plus le pont Doctrine ORM (paquet séparé
  # depuis la 3.2). Il doit être requis dans la même commande que orm-pack :
  # sinon le cache:clear post-install de orm-pack tourne avec API Platform
  # déjà actif mais sans le pont, et casse sur « Doctrine support cannot be
  # enabled as the doctrine ORM component is not installed ».
  composer require --no-interaction symfony/orm-pack api-platform/doctrine-orm
  composer require --no-interaction symfony/messenger symfony/amqp-messenger
  composer require --no-interaction --dev symfony/maker-bundle
else
  echo "→ Ajout du support Messenger/AMQP au projet full-stack"
  composer require --no-interaction symfony/amqp-messenger
fi

# -----------------------------------------------------------------------------
# Configuration locale : .env.local n'est pas versionné et surcharge .env.
# On y pointe les DSN vers les noms de services Docker (`database`, `rabbitmq`),
# résolus par le DNS interne du réseau Compose.
# -----------------------------------------------------------------------------
cat > .env.local <<LOCALENV
# Généré automatiquement à l'initialisation du projet — non versionné.
APP_ENV=dev
DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB}?serverVersion=16&charset=utf8"
MESSENGER_TRANSPORT_DSN="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@rabbitmq:5672/%2f/messages"
LOCALENV

echo "✔ Projet Symfony initialisé."
EOF

# -----------------------------------------------------------------------------
# 5.6 docker/nginx/default.conf
# -----------------------------------------------------------------------------
cat > docker/nginx/default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    # La racine web pointe sur public/ : seul ce dossier est exposé.
    root /var/www/backend/public;

    # Toute URL inconnue est renvoyée au contrôleur frontal de Symfony.
    location / {
        try_files $uri /index.php$is_args$args;
    }

    # Exécution du contrôleur frontal via FastCGI vers le conteneur php-fpm.
    location ~ ^/index\.php(/|$) {
        fastcgi_pass backend:9000;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;

        # $realpath_root résout les liens symboliques : indispensable pour que
        # les chemins vus par PHP correspondent à ceux du montage.
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;

        # `internal` : empêche l'accès direct à /index.php depuis l'extérieur.
        internal;
    }

    # Sécurité : aucun autre .php ne doit être exécutable.
    location ~ \.php$ {
        return 404;
    }

    client_max_body_size 32m;
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;
}
EOF

# -----------------------------------------------------------------------------
# 5.7 docker-compose.yml
# -----------------------------------------------------------------------------
# Heredoc QUOTÉ : les ${...} sont interprétés par Docker Compose au runtime,
# à partir du fichier .env généré plus haut (donc valeurs figées).
cat > docker-compose.yml <<'EOF'
# =============================================================================
# Stack de développement — généré par create-symfony-project.sh
# La clé `version:` est volontairement absente : obsolète en Compose v2.
# =============================================================================

services:

  # ---------------------------------------------------------------------------
  # backend : PHP-FPM + symfony-cli. Contient le code Symfony.
  # ---------------------------------------------------------------------------
  backend:
    build:
      # Le contexte est la racine du projet : les stages de déploiement doivent
      # pouvoir copier ./backend. Voir .dockerignore pour ce qui est exclu.
      context: .
      dockerfile: docker/php/Dockerfile
      # `target` est essentiel : sans lui, Docker construirait le dernier stage
      # du fichier (preprod), qui exige un composer.json déjà présent.
      target: dev
      args:
        # Les versions et l'identité hôte sont injectées au build depuis .env.
        PHP_TAG: ${PHP_TAG}
        COMPOSER_TAG: ${COMPOSER_TAG}
        SYMFONY_CLI_VERSION: ${SYMFONY_CLI_VERSION}
        AMQP_EXT_VERSION: ${AMQP_EXT_VERSION}
        UID: ${UID}
        GID: ${GID}
    container_name: ${COMPOSE_PROJECT_NAME}_backend
    restart: unless-stopped
    environment:
      # Consommées par le script init-symfony et par l'application.
      SYMFONY_VERSION: ${SYMFONY_VERSION}
      API_PLATFORM_VERSION: ${API_PLATFORM_VERSION}
      BACKEND_FLAVOR: ${BACKEND_FLAVOR}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      RABBITMQ_USER: ${RABBITMQ_USER}
      RABBITMQ_PASSWORD: ${RABBITMQ_PASSWORD}
    volumes:
      # Bind mount : le code vit sur l'hôte, l'IDE l'édite directement.
      - ./backend:/var/www/backend
    depends_on:
      database:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    networks: [app]

  # ---------------------------------------------------------------------------
  # web : nginx, unique point d'entrée HTTP du backend.
  # ---------------------------------------------------------------------------
  web:
    image: nginx:${NGINX_TAG}
    container_name: ${COMPOSE_PROJECT_NAME}_web
    restart: unless-stopped
    ports:
      - "${HTTP_PORT}:80"
    volumes:
      # Le code est monté en lecture seule : nginx n'a besoin que de servir
      # les assets statiques et de connaître le chemin de public/index.php.
      - ./backend:/var/www/backend:ro
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - backend
    networks: [app]

  # ---------------------------------------------------------------------------
  # database : PostgreSQL
  # ---------------------------------------------------------------------------
  database:
    image: postgres:${POSTGRES_TAG}
    container_name: ${COMPOSE_PROJECT_NAME}_database
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "${POSTGRES_PORT}:5432"
    volumes:
      # Volume nommé : les données survivent aux `docker compose down`.
      - db_data:/var/lib/postgresql/data
    healthcheck:
      # Permet à `backend` d'attendre que la base accepte réellement les
      # connexions (condition: service_healthy) plutôt que son simple démarrage.
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks: [app]

  # ---------------------------------------------------------------------------
  # rabbitmq : broker de messages pour Symfony Messenger
  # ---------------------------------------------------------------------------
  rabbitmq:
    image: rabbitmq:${RABBITMQ_TAG}
    container_name: ${COMPOSE_PROJECT_NAME}_rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD}
    ports:
      - "${RABBITMQ_PORT}:5672"      # protocole AMQP
      - "${RABBITMQ_UI_PORT}:15672"  # interface d'administration web
    volumes:
      - mq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 10s
      retries: 10
    networks: [app]

volumes:
  db_data:
  mq_data:

networks:
  app:
    driver: bridge
EOF

# -----------------------------------------------------------------------------
# 5.8 docker-compose.override.yml — service frontend (uniquement si --frontend)
# -----------------------------------------------------------------------------
# On passe par un fichier d'override, chargé automatiquement par Compose : le
# fichier principal reste identique dans les deux modes, ce qui simplifie la
# comparaison entre projets.
if (( WITH_FRONTEND )); then
cat > docker-compose.override.yml <<'EOF'
# =============================================================================
# Service frontend dédié (Node + Vite).
# Chargé automatiquement par Docker Compose en complément de docker-compose.yml.
# =============================================================================

services:

  frontend:
    image: node:${NODE_TAG}
    container_name: ${COMPOSE_PROJECT_NAME}_frontend
    restart: unless-stopped
    working_dir: /app

    # Gestion des droits, version « sans build » : le conteneur tourne
    # directement sous l'UID/GID de l'hôte. Les fichiers générés par Vite et
    # npm appartiennent donc au dev et sont éditables depuis l'IDE.
    user: "${UID}:${GID}"

    environment:
      # L'utilisateur injecté n'a pas forcément de home dans l'image : on
      # redirige HOME et le cache npm vers des chemins toujours accessibles en
      # écriture, sinon `npm install` échoue avec EACCES.
      HOME: /tmp
      NPM_CONFIG_CACHE: /tmp/.npm
      # Nécessaire dans un conteneur : le hot-reload de Vite ne reçoit pas
      # toujours les événements inotify à travers un bind mount.
      CHOKIDAR_USEPOLLING: "true"
      # URL de l'API exposée par le backend, consommée par le code front.
      VITE_API_URL: "http://localhost:${HTTP_PORT}"

    volumes:
      - ./frontend:/app

    ports:
      - "${VITE_PORT}:5173"

    # stdin/tty ouverts : indispensable pour pouvoir lancer des commandes
    # interactives (npm create vite) via `docker compose run`.
    stdin_open: true
    tty: true

    # Au démarrage : si le projet n'existe pas encore, on l'indique clairement
    # plutôt que de boucler en erreur. Sinon, install + serveur de dev.
    command: >
      sh -c "if [ ! -f package.json ]; then
               echo 'Projet Vite absent. Lancez : make front-init';
               sleep infinity;
             else
               npm install && npm run dev -- --host 0.0.0.0 --port 5173;
             fi"

    depends_on:
      - backend

    networks: [app]
EOF

# -----------------------------------------------------------------------------
# 5.8b docker/node/Dockerfile — images déployables du frontend
# -----------------------------------------------------------------------------
# En développement, le service `frontend` utilise l'image Node officielle telle
# quelle et lance `npm run dev` : il n'y a rien à construire. Ce Dockerfile ne
# sert donc QUE pour les environnements déployés, où Vite ne tourne pas — il a
# produit des fichiers statiques, servis par nginx.
cat > docker/node/Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
# =============================================================================
# Frontend — image déployable
# -----------------------------------------------------------------------------
#  Cibles (--target) :
#    production  nginx servant le bundle Vite compilé et minifié.
#    preprod     production + fichiers .map, pour des stacks lisibles.
#
#  Le principe appliqué au backend est conservé : `preprod` est construit
#  FROM production. Les fichiers JS/CSS servis sont donc BIT À BIT IDENTIQUES
#  entre les deux images — seules s'ajoutent les source maps, qui ne modifient
#  pas le bundle exécuté. On valide bien l'artefact que l'on déploiera.
#
#  Contexte de build : racine du projet (cf. .dockerignore).
# =============================================================================

ARG NODE_TAG
ARG NGINX_TAG

# =============================================================================
# Stage : deps — installation des dépendances npm
# Isolé pour le cache : tant que package-lock.json ne change pas, cette couche
# n'est pas rejouée, même si tout le code source est modifié.
# =============================================================================
FROM node:${NODE_TAG} AS deps

WORKDIR /app

# `npm ci` (et non `npm install`) : installation strictement conforme au
# lockfile, reproductible, et qui échoue si le lock est désynchronisé.
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

# =============================================================================
# Stage : build — compilation Vite
# =============================================================================
FROM node:${NODE_TAG} AS build

WORKDIR /app

# ATTENTION : Vite inline les variables VITE_* AU MOMENT DU BUILD, dans le
# bundle. Ce ne sont donc pas des variables d'exécution : changer l'URL de l'API
# impose de reconstruire l'image. C'est la raison du --build-arg ci-dessous.
ARG VITE_API_URL
ENV VITE_API_URL=${VITE_API_URL}

COPY --from=deps /app/node_modules ./node_modules
COPY frontend/ ./

# Les source maps sont générées SYSTÉMATIQUEMENT, y compris pour la production.
# Elles ne changent pas le bundle : ce sont des fichiers séparés. On les isole
# ensuite pour ne les embarquer que dans l'image de préprod.
RUN set -eux; \
    npm run build -- --sourcemap; \
    mkdir -p /out/app /out/maps; \
    cp -a dist/. /out/app/; \
    # Déplacement (et non copie) des .map hors du répertoire servi en prod.
    find /out/app -name '*.map' -exec sh -c \
        'mkdir -p "/out/maps/$(dirname "${1#/out/app/}")"; mv "$1" "/out/maps/${1#/out/app/}"' _ {} \;

# =============================================================================
# Stage : production — nginx servant les fichiers statiques
# =============================================================================
FROM nginx:${NGINX_TAG} AS production

# Port non privilégié : permet de tourner en utilisateur non-root, donc
# `runAsNonRoot: true` côté Kubernetes.
EXPOSE 8080

COPY docker/node/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /out/app /usr/share/nginx/html

# nginx a besoin d'écrire son PID et ses caches temporaires. On les redirige
# vers /tmp afin que le reste du système de fichiers puisse rester en lecture
# seule (readOnlyRootFilesystem).
RUN set -eux; \
    sed -i 's|^pid .*|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf; \
    chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx

USER nginx

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD ["wget", "-qO-", "http://127.0.0.1:8080/healthz"]

CMD ["nginx", "-g", "daemon off;"]

# =============================================================================
# Stage : preprod — production + source maps
# =============================================================================
FROM production AS preprod

USER root
# Seul ajout : les .map, qui rendent les stacks d'erreur lisibles dans les
# outils de suivi (Sentry, console navigateur) sans toucher au code exécuté.
COPY --from=build --chown=nginx:nginx /out/maps /usr/share/nginx/html
USER nginx
EOF

# -----------------------------------------------------------------------------
# 5.8c docker/node/nginx.conf — service des fichiers statiques
# -----------------------------------------------------------------------------
cat > docker/node/nginx.conf <<'EOF'
server {
    listen 8080;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Sonde de vivacité : réponse immédiate, sans accès disque.
    location = /healthz {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    # Les assets générés par Vite portent un hash dans leur nom : leur contenu
    # ne change jamais pour une URL donnée, on peut donc les mettre en cache
    # indéfiniment.
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # index.html ne doit JAMAIS être mis en cache : c'est lui qui référence les
    # nouveaux assets hashés après un déploiement.
    location = /index.html {
        add_header Cache-Control "no-store, must-revalidate";
    }

    # Routage côté client : toute URL inconnue renvoie l'application, qui se
    # charge d'afficher la bonne vue (ou sa propre page 404).
    location / {
        try_files $uri $uri/ /index.html;
    }

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1024;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
}
EOF
fi

# -----------------------------------------------------------------------------
# 5.9 Makefile — raccourcis du quotidien
# -----------------------------------------------------------------------------
# Attention : dans un Makefile, les commandes sont indentées par des TABULATIONS.
# Le heredoc est quoté pour que `$$` (échappement du `$` make) reste littéral.
{
cat <<'EOF'
# Raccourcis du projet. `make help` liste les cibles disponibles.
.DEFAULT_GOAL := help
DC := docker compose

.PHONY: help build up down restart logs sh sh-front init db-migrate consume build-prod build-preprod front-init build-front-prod build-front-preprod

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Construit les images
	$(DC) build

up: ## Démarre la stack en arrière-plan
	$(DC) up -d

down: ## Arrête la stack (les volumes sont conservés)
	$(DC) down

restart: down up ## Redémarre la stack

logs: ## Suit les logs de tous les services
	$(DC) logs -f

sh: ## Ouvre un shell dans le backend, en tant qu'utilisateur dev
	$(DC) exec --user dev backend bash

init: ## (Re)joue l'initialisation du projet Symfony
	$(DC) run --rm --user dev backend init-symfony

db-migrate: ## Applique les migrations Doctrine
	$(DC) exec --user dev backend php bin/console doctrine:migrations:migrate --no-interaction

consume: ## Lance le worker Messenger (transport async)
	$(DC) exec --user dev backend php bin/console messenger:consume async -vv

# --- Images déployables ------------------------------------------------------
# Ces cibles n'utilisent PAS Docker Compose : elles produisent un artefact
# destiné à un registry, pas un conteneur local.
# Le tag par défaut reprend le SHA court du commit courant : chaque image est
# ainsi traçable jusqu'à la révision exacte du code qu'elle contient.
TAG ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
IMAGE ?= $(COMPOSE_PROJECT_NAME)-backend
FLAVOR := $(shell grep '^BACKEND_FLAVOR=' .env | cut -d= -f2)

build-prod: ## Construit l'image de production (TAG=... IMAGE=...)
	docker build \
	  --target production \
	  --build-arg PHP_TAG=$(shell grep '^PHP_TAG=' .env | cut -d= -f2) \
	  --build-arg COMPOSER_TAG=$(shell grep '^COMPOSER_TAG=' .env | cut -d= -f2) \
	  --build-arg AMQP_EXT_VERSION=$(shell grep '^AMQP_EXT_VERSION=' .env | cut -d= -f2) \
	  --build-arg BACKEND_FLAVOR=$(FLAVOR) \
	  -f docker/php/Dockerfile \
	  -t $(IMAGE):$(TAG) .

build-preprod: ## Construit l'image de préprod (= prod + outils de diagnostic)
	docker build \
	  --target preprod \
	  --build-arg PHP_TAG=$(shell grep '^PHP_TAG=' .env | cut -d= -f2) \
	  --build-arg COMPOSER_TAG=$(shell grep '^COMPOSER_TAG=' .env | cut -d= -f2) \
	  --build-arg AMQP_EXT_VERSION=$(shell grep '^AMQP_EXT_VERSION=' .env | cut -d= -f2) \
	  --build-arg XDEBUG_VERSION=$(shell grep '^XDEBUG_VERSION=' .env | cut -d= -f2) \
	  --build-arg BACKEND_FLAVOR=$(FLAVOR) \
	  -f docker/php/Dockerfile \
	  -t $(IMAGE):$(TAG)-preprod .
EOF

if (( WITH_FRONTEND )); then
cat <<'EOF'

sh-front: ## Ouvre un shell dans le conteneur frontend
	$(DC) exec frontend sh

front-init: ## Crée le projet Vite en mode INTERACTIF (à lancer une seule fois)
	$(DC) run --rm frontend npm create vite@$(shell grep '^CREATE_VITE_VERSION=' .env | cut -d= -f2) .

# --- Images déployables du frontend ------------------------------------------
# API_URL est inliné dans le bundle par Vite AU BUILD : il doit donc être fourni
# ici, et non au démarrage du conteneur.
FRONT_IMAGE ?= $(COMPOSE_PROJECT_NAME)-frontend
API_URL ?= http://localhost:8080

build-front-prod: ## Construit l'image frontend de production (API_URL=... TAG=...)
	docker build \
	  --target production \
	  --build-arg NODE_TAG=$(shell grep '^NODE_TAG=' .env | cut -d= -f2) \
	  --build-arg NGINX_TAG=$(shell grep '^NGINX_TAG=' .env | cut -d= -f2) \
	  --build-arg VITE_API_URL=$(API_URL) \
	  -f docker/node/Dockerfile \
	  -t $(FRONT_IMAGE):$(TAG) .

build-front-preprod: ## Construit l'image frontend de préprod (= prod + source maps)
	docker build \
	  --target preprod \
	  --build-arg NODE_TAG=$(shell grep '^NODE_TAG=' .env | cut -d= -f2) \
	  --build-arg NGINX_TAG=$(shell grep '^NGINX_TAG=' .env | cut -d= -f2) \
	  --build-arg VITE_API_URL=$(API_URL) \
	  -f docker/node/Dockerfile \
	  -t $(FRONT_IMAGE):$(TAG)-preprod .
EOF
fi
} > Makefile

# -----------------------------------------------------------------------------
# 5.10 .gitignore et README
# -----------------------------------------------------------------------------
cat > .gitignore <<'EOF'
# Environnement local (contient les identifiants et l'UID/GID du poste)
/.env.local
/.env.*.local

# Dépendances et artefacts de build
/backend/vendor/
/backend/var/
/backend/.env.local
/frontend/node_modules/
/frontend/dist/

# Éditeurs
.idea/
.vscode/
*.swp
.DS_Store
EOF

cat > README.md <<EOF
# ${PROJECT_NAME}

Projet Symfony dockerisé, généré le $(date +%F).
Mode backend : **$( (( WITH_FRONTEND )) && echo "API (API Platform) + frontend Vite dédié" || echo "full-stack (Symfony --webapp)" )**

## Services

| Service    | Rôle                    | Accès depuis l'hôte |
|------------|-------------------------|---------------------|
| \`web\`      | nginx                   | http://localhost:8080 |
| \`backend\`  | PHP-FPM + Symfony       | \`make sh\` |
| \`database\` | PostgreSQL              | localhost:5432 |
| \`rabbitmq\` | RabbitMQ + UI           | http://localhost:15672 |
$( (( WITH_FRONTEND )) && echo "| \`frontend\` | Node + Vite             | http://localhost:5173 |" )

## Commandes

\`\`\`bash
make help      # liste toutes les cibles
make up        # démarre la stack
make sh        # shell dans le backend (utilisateur dev)
make logs      # logs en direct
\`\`\`

## Droits d'accès

Les conteneurs \`backend\`$( (( WITH_FRONTEND )) && echo " et \`frontend\`" ) tournent sous l'UID/GID de
l'utilisateur qui a généré le projet (voir \`UID\`/\`GID\` dans \`.env\`). Les fichiers
créés dans les conteneurs sont donc directement éditables depuis l'IDE.

**Si un autre développeur clone le projet**, il doit adapter \`UID\`/\`GID\` dans
\`.env\` à son poste (\`id -u\` / \`id -g\`) puis relancer \`make build\`.

## Images et environnements

Le \`Dockerfile\` est multi-stage. Trois cibles sont exploitables :

| Cible        | Usage        | Code       | Construite via |
|--------------|--------------|------------|----------------|
| \`dev\`        | poste local  | bind mount | \`make build\` |
| \`production\` | déploiement  | copié      | \`make build-prod\` |
| \`preprod\`    | validation   | copié      | \`make build-preprod\` |

\`preprod\` est construite **à partir de** \`production\` : ses couches applicatives
sont identiques à l'octet près. Ce qui est validé en préprod est donc bien
l'artefact déployé, augmenté d'Xdebug en mode profilage déclenché manuellement
(\`XDEBUG_TRIGGER\`) — donc sans surcoût sur le trafic normal.

L'ordre du pipeline reste dev → préprod → prod, indépendamment de l'ordre de
déclaration dans le fichier, qui n'est qu'une contrainte de Docker.
$( (( WITH_FRONTEND )) && cat <<'FRONTDOC'

### Frontend

En développement, le service `frontend` utilise l'image Node officielle telle
quelle : il n'y a rien à construire, `make build` ne construit que le backend.

En déployé, Vite ne tourne pas — il a produit des fichiers statiques, servis par
nginx (`docker/node/Dockerfile`, cibles `production` et `preprod`) :

```bash
make build-front-prod    API_URL=https://api.exemple.com TAG=1.2.3
make build-front-preprod API_URL=https://api-preprod.exemple.com TAG=1.2.3
```

`API_URL` est obligatoire au build : Vite **inline** les variables `VITE_*` dans
le bundle. Changer l'URL de l'API impose donc de reconstruire l'image — ce n'est
pas un réglage d'exécution.

Là encore, `preprod` est construit `FROM production` : les fichiers JS/CSS
servis sont identiques, seules s'ajoutent les source maps.
FRONTDOC
)

\`\`\`bash
make build-prod TAG=1.2.3
make build-preprod TAG=1.2.3
\`\`\`

Sans \`TAG\`, le SHA court du commit courant est utilisé : chaque image reste
traçable jusqu'à la révision exacte du code qu'elle contient.

## Versions

Toutes les versions sont figées — voir \`versions.lock\` et le fichier \`.env\`.

Seule exception : **Composer**, épinglé sur sa branche majeure (\`composer:2\`).
Les correctifs 2.x sont donc récupérés à chaque \`make build\`, mais un futur
Composer 3 ne sera jamais installé sans modification explicite du \`.env\`.
EOF

# Dépôt git initialisé au niveau du projet (et non du seul dossier Symfony).
git init -q .
ok "Fichiers générés."

# -----------------------------------------------------------------------------
# 6. Build et initialisation
# -----------------------------------------------------------------------------
if (( DO_BUILD )); then
  info "Construction des images Docker…"
  docker compose build

  info "Initialisation du projet Symfony (mode : $( (( WITH_FRONTEND )) && echo api || echo full ))…"
  # --user dev : garantit que le code généré appartient à l'utilisateur hôte.
  docker compose run --rm --user dev backend init-symfony

  if (( WITH_FRONTEND )); then
    info "Création du projet Vite — répondez aux questions de l'assistant."
    # `docker compose run` alloue un TTY par défaut : le dev interagit
    # normalement avec le questionnaire de create-vite (nom, framework, variante).
    docker compose run --rm frontend npm create "vite@${CREATE_VITE_VERSION}" .
    # Installation initiale des dépendances choisies pendant le questionnaire.
    docker compose run --rm frontend npm install
  fi

  info "Démarrage de la stack…"
  docker compose up -d
  ok "Stack démarrée."
else
  warn "--no-build : aucune image construite. Lancez 'make build && make init' manuellement."
fi

# -----------------------------------------------------------------------------
# 7. Récapitulatif final
# -----------------------------------------------------------------------------
printf '\n%s================================================%s\n' "$C_OK" "$C_RESET"
ok "Projet '$PROJECT_NAME' prêt dans $PROJECT_DIR"
printf '\n'
printf '  Backend  : http://localhost:8080\n'
printf '  RabbitMQ : http://localhost:15672  (app / app)\n'
printf '  Postgres : localhost:5432          (app / app)\n'
(( WITH_FRONTEND )) && printf '  Frontend : http://localhost:5173\n'
printf '\n  Prochaine étape : cd %s && make help\n\n' "$PROJECT_DIR"
