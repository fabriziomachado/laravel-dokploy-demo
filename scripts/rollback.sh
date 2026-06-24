#!/bin/sh
# scripts/rollback.sh — rollback de versão no Swarm local
#
# Modos de uso:
#   sh scripts/rollback.sh              # rollback automático (volta para a versão anterior do Swarm)
#   sh scripts/rollback.sh abc1234      # rollback para uma tag específica do registry
#   sh scripts/rollback.sh --list       # lista todas as tags disponíveis no registry

set -e

REGISTRY="localhost:5000"
IMAGE="laravel-app"
STACK="laravel-demo"
SERVICE="${STACK}_app"
FULL_IMAGE="${REGISTRY}/${IMAGE}"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Laravel Swarm Rollback          ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Stack   : ${STACK}"
echo "║  Serviço : ${SERVICE}"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Listar tags disponíveis ────────────────────────────────────────────────────
list_tags() {
  echo "Tags disponíveis no registry (${REGISTRY}):"
  echo ""
  TAGS=$(curl -s "http://${REGISTRY}/v2/${IMAGE}/tags/list" | \
    python3 -c "import sys,json; tags=json.load(sys.stdin).get('tags',[]); [print('  ' + t) for t in sorted(tags) if t != 'latest']" 2>/dev/null || \
    curl -s "http://${REGISTRY}/v2/${IMAGE}/tags/list" | grep -o '"[a-f0-9]*"' | tr -d '"' | sort)
  echo "${TAGS}"
  echo ""
  echo "  latest → imagem mais recente"
  echo ""
}

# ── Versão atual ───────────────────────────────────────────────────────────────
current_image() {
  docker service inspect "${SERVICE}" \
    --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || echo "desconhecida"
}

# ── Modo --list ────────────────────────────────────────────────────────────────
if [ "$1" = "--list" ]; then
  list_tags
  echo "Versão atual em produção:"
  echo "  $(current_image)"
  echo ""
  echo "Para fazer rollback: sh scripts/rollback.sh <tag>"
  exit 0
fi

# ── Verificações ───────────────────────────────────────────────────────────────
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
  echo "❌ Docker Swarm não está ativo."
  exit 1
fi

if ! docker stack ls --format '{{.Name}}' | grep -q "^${STACK}$"; then
  echo "❌ Stack '${STACK}' não encontrado."
  exit 1
fi

CURRENT=$(current_image)
echo "Versão atual : ${CURRENT}"
echo ""

# ── Rollback para tag específica ───────────────────────────────────────────────
if [ -n "$1" ]; then
  TAG="$1"
  TARGET="${FULL_IMAGE}:${TAG}"

  echo "▶ Fazendo rollback para: ${TARGET}"
  echo ""

  docker service update \
    --image "${TARGET}" \
    --update-parallelism 1 \
    --update-delay 10s \
    --update-failure-action rollback \
    "${SERVICE}"

  echo ""
  echo "✔ Rollback concluído → ${TARGET}"

# ── Rollback automático do Swarm (volta para versão anterior) ──────────────────
else
  echo "Nenhuma tag especificada — usando rollback automático do Swarm."
  echo "(Volta para a versão imediatamente anterior do serviço)"
  echo ""

  docker service rollback "${SERVICE}"

  echo ""
  echo "✔ Rollback automático concluído"
fi

echo ""
echo "▶ Status atual das réplicas:"
sleep 3
docker stack ps "${STACK}" --format "table {{.Name}}\t{{.Image}}\t{{.CurrentState}}" | grep app
echo ""
echo "Para ver as tags disponíveis: sh scripts/rollback.sh --list"
