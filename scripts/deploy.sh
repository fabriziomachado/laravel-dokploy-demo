#!/bin/sh
# scripts/deploy.sh — build, tag por git SHA e deploy no Swarm local
#
# Simula o fluxo que o Dokploy executa a cada push:
#   1. Gera tag a partir do SHA do commit atual
#   2. Builda a imagem com a tag SHA + latest
#   3. Faz push para o registry local (:5000)
#   4. Rolling update no Swarm (uma réplica por vez)
#
# Uso:
#   sh scripts/deploy.sh              # usa o SHA do HEAD atual
#   sh scripts/deploy.sh abc1234      # usa uma tag específica (ex: para redeploy)

set -e

REGISTRY="localhost:5000"
IMAGE="laravel-app"
STACK="laravel-demo"
SERVICE="${STACK}_app"

# ── Tag ────────────────────────────────────────────────────────────────────────
if [ -n "$1" ]; then
  TAG="$1"
  # Se a tag já existe no registry, usá-la diretamente sem rebuildar.
  # Rebuildar com uma SHA antiga geraria uma imagem mentirosa (código diferente do commit).
  if curl -sf "http://${REGISTRY}/v2/${IMAGE}/manifests/${TAG}" > /dev/null 2>&1; then
    echo "Tag '${TAG}' já existe no registry — pulando build e fazendo deploy direto."
    echo "(Para rebuildar, use: docker image rm localhost:5000/${IMAGE}:${TAG} primeiro)"
    SKIP_BUILD=1
  fi
else
  TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "manual")
fi

FULL_IMAGE="${REGISTRY}/${IMAGE}"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           Laravel Swarm Deploy           ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Stack   : ${STACK}"
echo "║  Tag     : ${TAG}"
echo "║  Imagem  : ${FULL_IMAGE}:${TAG}"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Verificações ───────────────────────────────────────────────────────────────
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
  echo "❌ Docker Swarm não está ativo. Execute: docker swarm init"
  exit 1
fi

if ! curl -s http://${REGISTRY}/v2/ > /dev/null 2>&1; then
  echo "❌ Registry local não encontrado. Execute:"
  echo "   docker run -d -p 5000:5000 --name registry --restart=always registry:2"
  exit 1
fi

# ── Build ──────────────────────────────────────────────────────────────────────
if [ "${SKIP_BUILD}" != "1" ]; then
  echo "▶ [1/4] Building image..."
  docker build \
    -t "${FULL_IMAGE}:${TAG}" \
    -t "${FULL_IMAGE}:latest" \
    .
  echo "✔ Build concluído: ${FULL_IMAGE}:${TAG}"
  echo ""

  echo "▶ [2/4] Pushing para o registry..."
  docker push "${FULL_IMAGE}:${TAG}"
  docker push "${FULL_IMAGE}:latest"
  echo "✔ Push concluído"
  echo ""
else
  echo "▶ [1/4] Build ignorado (tag já existe no registry)"
  echo "▶ [2/4] Push ignorado"
  echo ""
fi

# ── Deploy ou primeiro deploy ──────────────────────────────────────────────────
if docker stack ls --format '{{.Name}}' | grep -q "^${STACK}$"; then
  echo "▶ [3/4] Rolling update do serviço ${SERVICE}..."
  docker service update \
    --image "${FULL_IMAGE}:${TAG}" \
    --update-parallelism 1 \
    --update-delay 10s \
    --update-failure-action rollback \
    "${SERVICE}"
  echo "✔ Rolling update concluído"
else
  echo "▶ [3/4] Primeiro deploy — criando stack ${STACK}..."

  if [ -z "${APP_KEY}" ]; then
    echo "❌ APP_KEY não definido. Execute:"
    echo "   export APP_KEY=base64:..."
    exit 1
  fi

  if [ -z "${DB_PASSWORD}" ]; then
    echo "❌ DB_PASSWORD não definido. Execute:"
    echo "   export DB_PASSWORD=sua_senha"
    exit 1
  fi

  TAG="${TAG}" docker stack deploy -c docker-stack.yml "${STACK}"
  echo "✔ Stack criado"
fi
echo ""

# ── Status ─────────────────────────────────────────────────────────────────────
echo "▶ [4/4] Aguardando convergência..."
sleep 5
docker stack ps "${STACK}" --format "table {{.Name}}\t{{.Image}}\t{{.CurrentState}}" | grep app
echo ""
echo "✔ Deploy finalizado!"
echo ""
echo "  Imagem deployada : ${FULL_IMAGE}:${TAG}"
echo "  App               : http://localhost:8001"
echo "  MinIO Console     : http://localhost:9001"
echo ""
echo "  Para rollback     : sh scripts/rollback.sh"
