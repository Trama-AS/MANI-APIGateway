#!/usr/bin/env bash
# Verifica que el Gateway no expone las rutas internas de Core que usa Dispatch (SCRUM-1073, ADR-0030 §2).
# Uso: tests/gateway/rutas-internas-core.sh [baseUrl]   (por defecto http://localhost)
set -u
BASE="${1:-http://localhost}"
fallos=0

esperar() {
  local metodo="$1" ruta="$2" esperado="$3" obtenido
  obtenido=$(curl -s -k -L -o /dev/null -w '%{http_code}' -X "$metodo" -H 'Authorization: Bearer token-de-cliente' "$BASE$ruta")
  if [ "$obtenido" = "$esperado" ]; then
    echo "ok   $metodo $ruta -> $obtenido"
  else
    echo "FALLA $metodo $ruta -> $obtenido (esperado $esperado)"
    fallos=$((fallos + 1))
  fi
}

# Bloqueadas: ninguna llega a Core, con cualquier mayúscula, barra final o prefijo /api/v1 repetido.
for metodo in GET POST; do
  esperar "$metodo" /api/v1/core/allies/eligible 404
  esperar "$metodo" /api/v1/core/allies/eligible/ 404
  esperar "$metodo" /api/v1/core/Allies/Eligible 404
  esperar "$metodo" /api/v1/core/api/v1/allies/eligible 404
  esperar "$metodo" '/api/v1/core/allies/eligible?categoriaId=x' 404
  esperar "$metodo" /api/v1/core/solicitudes/0a1b2c3d-0000-4000-8000-000000000001/context 404
  esperar "$metodo" /api/v1/core/api/v1/solicitudes/abc/CONTEXT 404
  esperar "$metodo" /api/v1/core/notifications 404
  esperar "$metodo" /api/v1/core/Notifications/ 404
  esperar "$metodo" /api/v1/core/api/v1/notifications 404
  esperar "$metodo" "/api/v1/core/notifications;x" 404
  esperar "$metodo" /api/v1/core/allies%2Feligible 404
  # Decisión 6A (SCRUM-1403): comando de asignación y bandeja de ofertas del aliado.
  esperar "$metodo" /api/v1/core/solicitudes/0a1b2c3d-0000-4000-8000-000000000001/asignacion 404
  esperar "$metodo" /api/v1/core/solicitudes/0a1b2c3d-0000-4000-8000-000000000001/asignacion/ 404
  esperar "$metodo" /api/v1/core/api/v1/solicitudes/abc/ASIGNACION 404
  esperar "$metodo" "/api/v1/core/solicitudes/abc/asignacion;x" 404
  esperar "$metodo" /api/v1/core/solicitudes/abc%2Fasignacion 404
  esperar "$metodo" /api/v1/core/allies/me/offers 404
  esperar "$metodo" /api/v1/core/Allies/Me/Offers/ 404
  esperar "$metodo" /api/v1/core/api/v1/allies/me/offers 404
  esperar "$metodo" "/api/v1/core/allies/me/offers;x" 404

  # TEC-09 (SCRUM-1456): dev-token y validate-token bloqueados al tráfico externo
  esperar "$metodo" /api/v1/core/auth/dev-token 404
  esperar "$metodo" /api/v1/core/auth/dev-token/ 404
  esperar "$metodo" /api/v1/core/auth/DEV-TOKEN 404
  esperar "$metodo" /api/v1/core/api/v1/core/auth/dev-token 404
  esperar "$metodo" "/api/v1/core/auth/dev-token;x" 404
  esperar "$metodo" /api/v1/core/auth/validate-token 404
  esperar "$metodo" /api/v1/core/auth/validate-token/ 404
  esperar "$metodo" /api/v1/core/auth/VALIDATE-TOKEN 404
  esperar "$metodo" /api/v1/core/api/v1/core/auth/validate-token 404
  esperar "$metodo" "/api/v1/core/auth/validate-token;x" 404
done

# Siguen pasando: el resto de Core no se ve afectado.
esperar GET /api/v1/core/health 200

if [ "$fallos" -gt 0 ]; then
  echo "$fallos verificaciones fallaron"
  exit 1
fi
echo "Rutas internas de Core cerradas en el Gateway"
