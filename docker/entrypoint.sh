#!/bin/sh
set -e

# Create database if not exists
if [ ! -f /app/database/database.sqlite ]; then
    echo "Creating database.sqlite..."
    touch /app/database/database.sqlite
fi

# Run migrations
echo "Running migrations..."
php artisan migrate --force

# Cache config
echo "Caching configuration..."
php artisan optimize

# Start FrankenPHP
echo "Starting FrankenPHP..."
exec "$@"
