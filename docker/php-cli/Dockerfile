FROM php:8.4-cli-alpine

COPY --from=mlocati/php-extension-installer:latest /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN apk add --no-cache \
    bash \
    git \
    unzip \
    && install-php-extensions \
    bcmath \
    intl \
    mbstring \
    pcntl \
    pdo_pgsql \
    pdo_sqlite \
    redis \
    xml \
    zip

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

WORKDIR /app

CMD ["php", "-v"]
