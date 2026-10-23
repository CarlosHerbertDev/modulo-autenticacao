FROM php:8.4.27-apache AS base

RUN apt-get update && apt-get install -y --no-install-recommends \
        unzip git zip \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" gd pdo pdo_mysql zip opcache bcmath \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN a2enmod rewrite headers
COPY docker/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY docker/apache-tuning.conf /etc/apache2/conf-available/zz-tuning.conf
RUN a2enconf zz-tuning
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-app.ini

WORKDIR /var/www/html


FROM base AS dev

RUN printf "opcache.validate_timestamps=1\nopcache.revalidate_freq=0\n" \
        > /usr/local/etc/php/conf.d/zz-opcache-dev.ini

COPY docker/entrypoint.dev.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


FROM base AS prod

RUN printf "opcache.validate_timestamps=0\nopcache.memory_consumption=192\nopcache.max_accelerated_files=20000\n" \
        > /usr/local/etc/php/conf.d/zz-opcache-prod.ini

COPY src/composer.json src/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY src/ ./
RUN mkdir -p storage/framework/cache/data storage/framework/sessions \
             storage/framework/views storage/logs storage/app/public \
    && composer dump-autoload --no-dev --optimize --classmap-authoritative \
    && php artisan package:discover --ansi \
    && chown -R www-data:www-data storage bootstrap/cache

COPY docker/entrypoint.prod.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 10000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
