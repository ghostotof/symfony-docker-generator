#!/bin/bash
set -e

echo "==> [FrankenPHP] Démarrage en mode DEV"
cd /var/www/app

# Dépendances Composer (seulement si le projet est initialisé)
if [ ! -d "vendor" ] && [ -f "composer.json" ]; then
    echo "==> vendor/ absent — composer install..."
    composer install --no-interaction --prefer-dist
fi

# Migrations
echo "==> Migrations Doctrine..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true

# Clés JWT
if [ ! -f "config/jwt/private.pem" ]; then
    echo "==> Génération des clés JWT..."
    php bin/console lexik:jwt:generate-keypair --skip-if-exists || true
fi

echo "==> Démarrage de FrankenPHP..."
exec "$@"
