#!/usr/bin/env bash
# Verifica el preflight CORS de las rutas que MANI-Flutter Web llama con encabezados propios.
# Newman y Playwright `request` no envían Origin ni hacen preflight: sin este caso, un encabezado
# que el Gateway no permite (Idempotency-Key en PROD, 22 oct 2026) solo se ve en el navegador.
# Uso: tests/gateway/cors-preflight.sh [baseUrl] [origin]
#   (por defecto http://localhost y http://localhost:8080, el origen de Flutter Web)
set -u
BASE="${1:-http://localhost}"
ORIGEN="${2:-http://localhost:8080}"
fallos=0

# preflight <metodo> <ruta> <encabezados que pide la app, en minúscula y separados por coma>
preflight() {
  local metodo="$1" ruta="$2" pedidos="$3" respuesta codigo permitidos origen_resp faltan=""
  respuesta=$(curl -s -k -L -o /dev/null -D - -X OPTIONS \
    -H "Origin: $ORIGEN" \
    -H "Access-Control-Request-Method: $metodo" \
    -H "Access-Control-Request-Headers: $pedidos" \
    "$BASE$ruta" | tr -d '\r')
  codigo=$(printf '%s\n' "$respuesta" | awk 'NR==1 {print $2}')
  permitidos=$(printf '%s\n' "$respuesta" | grep -ai '^access-control-allow-headers:' | cut -d: -f2- | tr 'A-Z' 'a-z' | tr -d ' ')
  origen_resp=$(printf '%s\n' "$respuesta" | grep -ai '^access-control-allow-origin:' | cut -d: -f2- | tr -d ' ')
  local IFS=','
  for encabezado in $pedidos; do
    case ",$permitidos," in
      *",$encabezado,"*) ;;
      *) faltan="$faltan $encabezado" ;;
    esac
  done
  if [ "$codigo" != "204" ] && [ "$codigo" != "200" ]; then
    echo "FALLA OPTIONS $ruta ($metodo) -> $codigo (esperado 204)"
    fallos=$((fallos + 1))
  elif [ "$origen_resp" != "*" ] && [ "$origen_resp" != "$ORIGEN" ]; then
    echo "FALLA OPTIONS $ruta ($metodo) -> Allow-Origin '${origen_resp}' no admite $ORIGEN"
    fallos=$((fallos + 1))
  elif [ -n "$faltan" ]; then
    echo "FALLA OPTIONS $ruta ($metodo) -> Allow-Headers no incluye:$faltan"
    fallos=$((fallos + 1))
  else
    echo "ok    OPTIONS $ruta ($metodo) -> $codigo"
  fi
}

# Encabezados que agrega GatewayClient a toda petición (Accept es simple y no entra al preflight).
base='authorization,content-type,x-correlation-id'

# Publicar solicitud: el datasource agrega Idempotency-Key (solicitudes_cliente_remote_datasource.dart).
preflight POST /api/v1/core/solicitudes "$base,idempotency-key"
preflight POST /api/v1/core/solicitudes "$base,x-idempotency-key"
# Registro y login: sin token, con X-Tenant-Slug (auth_remote_data_source.dart).
preflight POST /api/v1/core/auth/register/client "content-type,x-correlation-id,x-tenant-slug"
preflight POST /api/v1/core/auth/register/ally "content-type,x-correlation-id,x-tenant-slug"
preflight POST /api/v1/core/auth/register/ally/company "content-type,x-correlation-id,x-tenant-slug"
preflight GET /api/v1/core/legal/documents/active "x-correlation-id,x-tenant-slug"
# Rutas autenticadas de cada servicio.
preflight GET /api/v1/core/profiles/me "$base"
preflight POST /api/v1/core/legal/consents "$base"
preflight GET /api/v1/rules/health "$base"
preflight POST /api/v1/dispatch/requests/orchestrate "$base"

if [ "$fallos" -gt 0 ]; then
  echo "$fallos verificaciones de CORS fallaron"
  exit 1
fi
echo "Preflight CORS aceptado para los encabezados que envía Flutter Web"
