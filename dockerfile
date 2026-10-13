FROM php:8.2.18-apache

RUN apt-get update && \
    apt-get install -y \
        unzip \
        git \
        zip \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev && \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \
    docker-php-ext-install -j$(nproc) gd

RUN docker-php-ext-install pdo pdo_mysql

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/html/public|g' /etc/apache2/sites-available/000-default.conf
