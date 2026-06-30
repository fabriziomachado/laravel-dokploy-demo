#!/bin/sh
set -e

if [ -z "${DB_HOST}" ] || [ -z "${DB_DATABASE}" ]; then
  echo "ERRO: DB_HOST e DB_DATABASE devem estar definidos (aba Environment do Dokploy)."
  exit 1
fi

echo "Aguardando Postgres em ${DB_HOST}:${DB_PORT}..."
until php -r "new PDO('pgsql:host='.getenv('DB_HOST').';port='.getenv('DB_PORT').';dbname='.getenv('DB_DATABASE'), getenv('DB_USERNAME'), getenv('DB_PASSWORD'));" 2>/dev/null; do
  sleep 2
done

if [ "$1" = "php" ] && [ "$3" = "migrate" ]; then
  php artisan config:clear
else
  php artisan optimize
fi

exec "$@"
