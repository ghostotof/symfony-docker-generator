#!/bin/bash
set -e

echo "==> [FrankenPHP] Démarrage en mode PROD"
cd /var/www/app

echo "==> Migrations Doctrine..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

exec "$@"
