#!/bin/sh
set -e

# Wait for database to be ready
echo "Waiting for database..."
until php -r "
try {
    \$driver = getenv('DB_CONNECTION') ?: 'pgsql';
    \$host   = getenv('DB_HOST')       ?: 'postgres';
    \$port   = getenv('DB_PORT')       ?: 5432;
    \$db     = getenv('DB_DATABASE')   ?: 'laravel';
    \$user   = getenv('DB_USERNAME')   ?: 'laravel';
    \$pass   = getenv('DB_PASSWORD')   ?: '';
    new PDO(\"\$driver:host=\$host;port=\$port;dbname=\$db\", \$user, \$pass);
    exit(0);
} catch (Exception \$e) {
    exit(1);
}
" 2>/dev/null; do
    echo "Database not ready, retrying in 2s..."
    sleep 2
done
echo "Database ready!"

# Ensure required storage directories exist (volume may be empty on first boot)
mkdir -p /app/storage/framework/cache/data
mkdir -p /app/storage/framework/sessions
mkdir -p /app/storage/framework/views
mkdir -p /app/storage/logs
chmod -R 777 /app/storage /app/bootstrap/cache

# Run migrations
echo "Running migrations..."
php artisan migrate --force

# Cache config
echo "Caching configuration..."
php artisan optimize

# Start FrankenPHP
echo "Starting FrankenPHP..."
exec "$@"
