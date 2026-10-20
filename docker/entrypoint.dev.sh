#!/bin/bash
set -e

if [ ! -f vendor/autoload.php ]; then
    composer install --no-interaction --prefer-dist
fi

if [ ! -f .env ]; then
    cp .env.example .env
    php artisan key:generate
fi

chown -R www-data:www-data storage bootstrap/cache
php artisan config:clear

exec apache2-foreground
