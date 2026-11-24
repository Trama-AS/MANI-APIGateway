#!/usr/bin/env bash
# SCRUM-1675 (T-38): Simulacro y procedimiento de rollback cronometrado en QA <= 5 min.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <servicio_compose> <imagen_con_digest_o_tag>" >&2
  echo "Ejemplo: $0 gateway ghcr.io/trama-as/mani-apigateway@sha256:cd4da004..." >&2
  exit 1
fi

SERVICE="$1"
TARGET_IMAGE="$2"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/mani}"
COMPOSE_FILE="${COMPOSE_FILE:-${DEPLOY_DIR}/docker-compose.qa.yml}"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/.env.qa}"
OVERRIDE_FILE="${OVERRIDE_FILE:-${DEPLOY_DIR}/docker-compose.rollback.override.yml}"
MAX_SECONDS="${MAX_SECONDS:-300}"

START_TS=$(date +%s)
echo "=== [SCRUM-1675] Inicio rollback QA servicio=${SERVICE}: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

if [ ! -f "$COMPOSE_FILE" ] || [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Faltan $COMPOSE_FILE o $ENV_FILE" >&2
  exit 1
fi

cd "$DEPLOY_DIR"

cat > "$OVERRIDE_FILE" <<EOF
services:
  ${SERVICE}:
    image: ${TARGET_IMAGE}
EOF

echo "-> Validando Compose con override de rollback (${TARGET_IMAGE})"
docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" --env-file "$ENV_FILE" config -q

echo "-> Descargando imagen objetivo (${TARGET_IMAGE})"
docker pull "$TARGET_IMAGE"

echo "-> Recreando servicio ${SERVICE}"
docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" --env-file "$ENV_FILE" up -d --no-deps "$SERVICE"

echo "-> Verificando salud tras rollback (timeout 120s)"
endpoints=(
  "http://127.0.0.1/health"
  "http://127.0.0.1/api/v1/core/health"
  "http://127.0.0.1/api/v1/rules/health"
  "http://127.0.0.1/api/v1/dispatch/health"
  "https://127.0.0.1:8080/"
  "http://127.0.0.1:3001/"
)

deadline=$(( $(date +%s) + 120 ))
while true; do
  all_ok=1
  for url in "${endpoints[@]}"; do
    # -k: el 8080 usa el certificado autofirmado del Gateway (SCRUM-1718)
    code=$(curl -sk -o /dev/null -w "%{http_code}" -m 3 "$url" || echo "000")
    if [ "$code" != "200" ]; then
      all_ok=0
      break
    fi
  done
  if [ "$all_ok" -eq 1 ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: Timeout esperando 200 OK tras rollback" >&2
    exit 1
  fi
  sleep 2
done

if [ -x "${DEPLOY_DIR}/check-qa.sh" ]; then
  "${DEPLOY_DIR}/check-qa.sh"
fi

END_TS=$(date +%s)
ELAPSED=$(( END_TS - START_TS ))
echo "=== [SCRUM-1675] Fin rollback QA: $(date -u +%Y-%m-%dT%H:%M:%SZ) | Duracion: ${ELAPSED}s (limite ${MAX_SECONDS}s) ==="
echo "NOTA: Para volver a :staging, ejecute desplegar_release_qa.sh (retira ${OVERRIDE_FILE})."

if [ "$ELAPSED" -gt "$MAX_SECONDS" ]; then
  echo "ADVERTENCIA: Rollback (${ELAPSED}s) supero el limite de ${MAX_SECONDS}s" >&2
  exit 1
fi
