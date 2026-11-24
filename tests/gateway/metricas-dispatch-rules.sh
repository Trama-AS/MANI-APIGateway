#!/usr/bin/env bash
# SCRUM-1714: las métricas de Dispatch y Rules llegan por el Gateway con la misma regla que /metrics de Core.
# Necesita Dispatch y Rules levantados detrás del Gateway (QA o docker compose completo); el CI del Gateway
# solo levanta Core, por eso no corre aquí.
# Uso: tests/gateway/metricas-dispatch-rules.sh [baseUrl]   (por defecto http://localhost)
set -u
BASE="${1:-http://localhost}"
fallos=0

esperar() {
  local descripcion="$1" esperado="$2" obtenido
  shift 2
  obtenido=$(curl -s -k -L -o /dev/null -w '%{http_code}' "$@")
  if [ "$obtenido" = "$esperado" ]; then
    echo "ok    $descripcion -> $obtenido"
  else
    echo "FALLA $descripcion -> $obtenido (esperado $esperado)"
    fallos=$((fallos + 1))
  fi
}

esperar_contenido() {
  local descripcion="$1" ruta="$2" patron="$3"
  if curl -s -k -L "$BASE$ruta" | grep -q "$patron"; then
    echo "ok    $descripcion -> contiene '$patron'"
  else
    echo "FALLA $descripcion -> no contiene '$patron'"
    fallos=$((fallos + 1))
  fi
}

esperar "GET /api/v1/dispatch/metrics sin token responde 200" 200 "$BASE/api/v1/dispatch/metrics"
esperar "GET /api/v1/rules/metrics sin token responde 200" 200 "$BASE/api/v1/rules/metrics"
esperar_contenido "Dispatch expone http_request_duration_seconds" "/api/v1/dispatch/metrics" "http_request_duration_seconds"
esperar_contenido "Rules expone http_server_requests_seconds" "/api/v1/rules/metrics" "http_server_requests_seconds"

if [ "$fallos" -gt 0 ]; then
  echo "$fallos verificaciones fallaron"
  exit 1
fi
echo "Dispatch y Rules exponen sus metricas Prometheus a traves del Gateway"
