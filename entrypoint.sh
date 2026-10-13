#!/bin/bash

echo ">>> Entrypoint iniciado em $(date)"

a2enmod rewrite

# ⚠️ Configurações abaixo são APENAS para Docker
# Para servidor compartilhado (Hostinger, Kinghost), use .htaccess ou php.ini
# Aumentar limites de upload e timeout do PHP

if ! [ -x "$(command -v composer)" ]; then
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
fi

if [ ! -f /var/www/html/artisan ]; then
    composer create-project laravel/laravel /var/www/html
fi

chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html

echo ">>> Apache iniciado em $(date)"
exec apache2-foreground