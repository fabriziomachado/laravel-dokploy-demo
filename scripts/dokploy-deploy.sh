#!/bin/sh
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
