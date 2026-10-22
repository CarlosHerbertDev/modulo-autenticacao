#!/bin/bash
set -e

: "${PORT:=10000}"
sed -ri "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

for var in APP_KEY DB_CONNECTION DB_HOST DB_DATABASE DB_USERNAME; do
    if [ -z "${!var}" ]; then
        echo "ERRO: variavel de ambiente ${var} nao definida." >&2
        exit 1
    fi
done

php artisan migrate --force --no-interaction

php artisan config:cache
php artisan route:cache
php artisan view:cache

exec apache2-foreground
