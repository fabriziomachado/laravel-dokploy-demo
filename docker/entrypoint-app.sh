#!/bin/sh
set -e

if [ "${RUN_OPTIMIZE:-true}" = "true" ]; then
    echo "Caching configuration..."
    php artisan optimize
fi

exec "$@"
