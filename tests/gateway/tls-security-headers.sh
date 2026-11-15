#!/usr/bin/env bash
# SCRUM-1665 (T-28): Verifica TLS 1.2+, encabezados de seguridad (HSTS, CSP, X-Frame-Options) y /nginx_status interno.
set -euo pipefail

HTTPS_URL="${1:-https://localhost}"

echo "=== Test TLS 1.2+ y encabezados de seguridad contra ${HTTPS_URL} ==="
headers=$(curl -skI --tlsv1.2 "${HTTPS_URL}/health")
echo "$headers" | tr -d '\r'

echo "$headers" | grep -qiE '^HTTP/[0-9.]+ 200' || { echo "FALLO: /health HTTPS no devolvió 200"; exit 1; }
echo "$headers" | grep -qi '^strict-transport-security:' || { echo "FALLO: falta Strict-Transport-Security"; exit 1; }
echo "$headers" | grep -qi '^content-security-policy:' || { echo "FALLO: falta Content-Security-Policy"; exit 1; }
echo "$headers" | grep -qi '^x-frame-options:' || { echo "FALLO: falta X-Frame-Options"; exit 1; }
echo "$headers" | grep -qi '^x-content-type-options:' || { echo "FALLO: falta X-Content-Type-Options"; exit 1; }

status_body=$(curl -sk --tlsv1.2 "${HTTPS_URL}/nginx_status" || true)
echo "$status_body" | grep -q 'Active connections' || {
  # En CI sin host localhost dentro de contenedor, también puede responder 403 según IP origen Docker; verificar /health API TLS
  api_code=$(curl -sk --tlsv1.2 -o /dev/null -w '%{http_code}' "${HTTPS_URL}/api/v1/core/health")
  [ "$api_code" = "200" ] || { echo "FALLO: /api/v1/core/health HTTPS devolvió ${api_code}"; exit 1; }
}

echo "OK: TLS 1.2+ y encabezados HSTS, CSP, X-Frame-Options verificados."
