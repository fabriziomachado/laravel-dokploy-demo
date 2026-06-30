#!/bin/sh
# Deploy manual (SSH no servidor Dokploy). NÃO use no campo Advanced → Command:
# o Dokploy sempre roda "docker <comando>" e não executa shell scripts.
# No Dokploy, use o comando documentado em docker-compose.build.yml.
set -e

STACK_NAME="${1:?Usage: dokploy-deploy.sh <stack-name>}"
IMAGE="ghcr.io/fabriziomachado/laravel-dokploy-demo"
IMAGE_TAG="${IMAGE_TAG:-latest}"

cd "$(dirname "$0")/.."

echo "Building ${IMAGE}:${IMAGE_TAG}..."
docker build -t "${IMAGE}:${IMAGE_TAG}" -t "${IMAGE}:latest" .

echo "Pushing to GHCR..."
docker push "${IMAGE}:${IMAGE_TAG}"
docker push "${IMAGE}:latest"

echo "Deploying stack ${STACK_NAME}..."
IMAGE_TAG="${IMAGE_TAG}" docker stack deploy \
  -c docker-compose.stack.yml \
  "${STACK_NAME}" \
  --prune \
  --with-registry-auth

echo "Done."
