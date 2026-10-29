#!/usr/bin/env bash
# Verifica que GET /api/v1/core/legal/documents/active es público en el Gateway (SCRUM-856, regresión R-01)
# y que el resto de /legal sigue protegido.
# Uso: tests/gateway/ruta-publica-legal.sh [baseUrl]   (por defecto http://localhost)
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

# Público: sin token llega a Core y responde 200 (con o sin X-Tenant-Slug).
esperar "GET documentos legales sin token y sin slug" 200 "$BASE/api/v1/core/legal/documents/active"
esperar "GET documentos legales sin token con slug" 200 -H 'X-Tenant-Slug: trama-demo' "$BASE/api/v1/core/legal/documents/active"

# Solo GET en la ruta pública.
esperar "POST a la ruta pública" 403 -X POST "$BASE/api/v1/core/legal/documents/active"

# El resto de /legal sigue pasando por auth_request: sin token, 401 del Gateway.
esperar "POST consentimiento sin token" 401 -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/v1/core/legal/consents"

if [ "$fallos" -gt 0 ]; then
  echo "$fallos verificaciones fallaron"
  exit 1
fi
echo "La ruta de documentos legales es pública y el resto de /legal sigue protegido"
