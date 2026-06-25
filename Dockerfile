FROM node:22-alpine AS assets

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY resources ./resources
COPY vite.config.js ./
RUN npm run build

FROM dunglas/frankenphp

# Install dependencies for Laravel
RUN install-php-extensions \
    bcmath \
    ctype \
    fileinfo \
    intl \
    json \
    mbstring \
    pdo \
    pdo_pgsql \
    pdo_sqlite \
    redis \
    tokenizer \
    xml \
    zip

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /app

# Install dependencies
COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --no-scripts \
    --optimize-autoloader \
    --prefer-dist

# Copy application code
COPY . /app
COPY --from=assets /app/public/build /app/public/build

RUN composer dump-autoload --no-dev --optimize \
    && php artisan package:discover --ansi

# Set permissions
RUN mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache

# Entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/app/Caddyfile"]
