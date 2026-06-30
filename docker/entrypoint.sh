#!/bin/sh
set -e

echo "Aguardando Postgres em ${DB_HOST}:${DB_PORT}..."
until php -r "new PDO('pgsql:host='.getenv('DB_HOST').';port='.getenv('DB_PORT'), getenv('DB_USERNAME'), getenv('DB_PASSWORD'));" 2>/dev/null; do
  sleep 2
done

php artisan optimize

exec "$@"
