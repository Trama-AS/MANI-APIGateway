#!/usr/bin/env bash
# Verifica que GET /metrics y GET /api/v1/core/metrics son accesibles a través del Gateway sin token (TEC-14, R-4)
# Uso: tests/gateway/ruta-publica-metrics.sh [baseUrl]   (por defecto http://localhost)
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

# Público: sin token llega a Core y responde 200 en /metrics y /api/v1/core/metrics
esperar "GET /metrics sin token responde 200" 200 "$BASE/metrics"
esperar "GET /api/v1/core/metrics sin token responde 200" 200 "$BASE/api/v1/core/metrics"

# Verifica formato Prometheus
esperar_contenido "GET /metrics contiene metricas http_requests_total" "/metrics" "http_requests_total"
esperar_contenido "GET /api/v1/core/metrics contiene metricas auth_validations_total" "/api/v1/core/metrics" "auth_validations_total"

if [ "$fallos" -gt 0 ]; then
  echo "$fallos verificaciones fallaron"
  exit 1
fi
echo "Los endpoints /metrics y /api/v1/core/metrics son publicos y exponen telemetria Prometheus correctamente"
