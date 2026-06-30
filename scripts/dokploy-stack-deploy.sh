#!/bin/sh
set -e

STACK_NAME="${STACK_NAME:-${1:?STACK_NAME ou COMPOSE_PROJECT_NAME obrigatório}}"
IMAGE="ghcr.io/fabriziomachado/laravel-dokploy-demo"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d%H%M%S)}"

cd "$(dirname "$0")/.."
export IMAGE_TAG

echo "==> IMAGE_TAG=${IMAGE_TAG}"
echo "==> STACK_NAME=${STACK_NAME}"

echo "==> Build..."
docker compose -f docker-compose.build.yml build

echo "==> Tag + push (${IMAGE_TAG} + latest)..."
docker tag "${IMAGE}:${IMAGE_TAG}" "${IMAGE}:latest"
docker push "${IMAGE}:${IMAGE_TAG}"
docker push "${IMAGE}:latest"

echo "==> Stack deploy..."
docker stack deploy \
  -c docker-compose.stack.yml \
  "${STACK_NAME}" \
  --prune \
  --with-registry-auth \
  --resolve-image always

echo "==> Rolling update (force)..."
docker service update --force "${STACK_NAME}_app"
docker service update --force "${STACK_NAME}_worker"

echo "==> Concluído. IMAGE_TAG=${IMAGE_TAG}"
