#!/bin/sh
# Atalho para deploy manual via SSH no servidor Dokploy.
exec "$(dirname "$0")/dokploy-stack-deploy.sh" "$@"
