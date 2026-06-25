#!/bin/sh
set -e

if [ "${DB_CONNECTION:-sqlite}" = "sqlite" ] && [ -n "${DB_DATABASE:-}" ] && [ ! -f "${DB_DATABASE}" ]; then
    echo "Creating database.sqlite..."
    mkdir -p "$(dirname "${DB_DATABASE}")"
    touch "${DB_DATABASE}"
fi

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    echo "Running migrations..."
    php artisan migrate --force
else
    echo "Skipping migrations. Run the migration service before scaling app replicas."
fi

# Cache config
echo "Caching configuration..."
php artisan optimize

# Start FrankenPHP
echo "Starting FrankenPHP..."
exec "$@"
