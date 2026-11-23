#!/usr/bin/env bash
# SCRUM-1674 (T-37): Despliegue cronometrado de release (:staging) en QA <= 10 min.
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/mani}"
COMPOSE_FILE="${COMPOSE_FILE:-${DEPLOY_DIR}/docker-compose.qa.yml}"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/.env.qa}"
OVERRIDE_FILE="${OVERRIDE_FILE:-${DEPLOY_DIR}/docker-compose.rollback.override.yml}"
MAX_SECONDS="${MAX_SECONDS:-600}"

START_TS=$(date +%s)
echo "=== [SCRUM-1674] Inicio despliegue QA (:staging): $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: No existe $COMPOSE_FILE" >&2
  exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: No existe $ENV_FILE" >&2
  exit 1
fi

cd "$DEPLOY_DIR"

if [ -f "$OVERRIDE_FILE" ]; then
  echo "-> Retirando override temporal de rollback ($OVERRIDE_FILE)"
  rm -f "$OVERRIDE_FILE"
fi

echo "-> Registrando digests previos en pre_deploy_digests.log"
{
  echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for img in $(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --images 2>/dev/null | sort -u); do
    digest=$(docker image inspect --format '{{index .RepoDigests 0}}' "$img" 2>/dev/null || echo "no-local")
    echo "$img => $digest"
  done
} > "${DEPLOY_DIR}/pre_deploy_digests.log"

echo "-> Validando Compose"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config -q

echo "-> Descargando imagenes :staging"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

echo "-> Recreando contenedores en QA"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

echo "-> Esperando salud de los 6 endpoints HTTP (timeout 180s)"
endpoints=(
  "http://127.0.0.1/health"
  "http://127.0.0.1/api/v1/core/health"
  "http://127.0.0.1/api/v1/rules/health"
  "http://127.0.0.1/api/v1/dispatch/health"
  "http://127.0.0.1:8080/"
  "http://127.0.0.1:3001/"
)

deadline=$(( $(date +%s) + 180 ))
while true; do
  all_ok=1
  for url in "${endpoints[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "$url" || echo "000")
    if [ "$code" != "200" ]; then
      all_ok=0
      break
    fi
  done
  if [ "$all_ok" -eq 1 ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: Timeout esperando endpoints 200 OK" >&2
    exit 1
  fi
  sleep 2
done

if [ -x "${DEPLOY_DIR}/check-qa.sh" ]; then
  "${DEPLOY_DIR}/check-qa.sh"
fi

END_TS=$(date +%s)
ELAPSED=$(( END_TS - START_TS ))
echo "=== [SCRUM-1674] Fin despliegue QA: $(date -u +%Y-%m-%dT%H:%M:%SZ) | Duracion: ${ELAPSED}s (limite ${MAX_SECONDS}s) ==="

if [ "$ELAPSED" -gt "$MAX_SECONDS" ]; then
  echo "ADVERTENCIA: Duracion (${ELAPSED}s) supero el objetivo de ${MAX_SECONDS}s" >&2
  exit 1
fi
