#!/usr/bin/env bash
# SCRUM-1718 (QAS-43): el 8080 ya no sirve la app ni la API por HTTP.
#   1. HTTP plano al 8080 recibe 301 a https://<host>:8080/... (no el contenido de la app).
#   2. HTTPS al 8080 negocia TLS 1.2+ y responde con HSTS.
#   3. TLS 1.1 o inferior se rechaza.
#   4. La app (flutter-web) se reenvía por la red interna y responde 200 por HTTPS.
# Uso: bash tests/gateway/puerto-8080-https.sh [host]   (por defecto localhost)
set -euo pipefail

HOST="${1:-localhost}"
HTTP_URL="http://${HOST}:8080"
HTTPS_URL="https://${HOST}:8080"

echo "=== SCRUM-1718: puerto 8080 solo por HTTPS en ${HOST} ==="

# 1. HTTP -> 301 a HTTPS en el mismo puerto
http_headers=$(curl -sI -m 5 "${HTTP_URL}/registro?x=1" | tr -d '\r')
echo "$http_headers"
echo "$http_headers" | grep -qE '^HTTP/[0-9.]+ 301' || { echo "FALLO: HTTP al 8080 no devolvió 301"; exit 1; }
echo "$http_headers" | grep -qi "^location: https://${HOST}:8080/registro?x=1$" \
  || { echo "FALLO: la redirección no apunta a ${HTTPS_URL}/registro?x=1"; exit 1; }
# El cuerpo debe ser la página corta del 301 de NGINX, nunca la app (ni el sustituto de flutter-web del CI).
http_body=$(curl -s -m 5 "${HTTP_URL}/")
echo "$http_body" | grep -qi '301 Moved Permanently' || { echo "FALLO: HTTP al 8080 no entregó la página del 301"; exit 1; }
if echo "$http_body" | grep -qiE 'flutter|Welcome to nginx'; then
  echo "FALLO: HTTP al 8080 entregó contenido de la app"; exit 1
fi

# 2. HTTPS con TLS 1.2+ y HSTS
health=$(curl -skI --tlsv1.2 -m 5 "${HTTPS_URL}/health" | tr -d '\r')
echo "$health"
echo "$health" | grep -qE '^HTTP/[0-9.]+ 200' || { echo "FALLO: ${HTTPS_URL}/health no devolvió 200"; exit 1; }
echo "$health" | grep -qi '^strict-transport-security:' || { echo "FALLO: falta Strict-Transport-Security en el 8080"; exit 1; }

# 3. TLS 1.1 o inferior se rechaza
if curl -sk --tlsv1 --tls-max 1.1 -o /dev/null -m 5 "${HTTPS_URL}/health" 2>/dev/null; then
  echo "FALLO: el 8080 aceptó TLS 1.1 o inferior"; exit 1
fi

# 4. La app llega por HTTPS a través del Gateway
app_code=$(curl -sk --tlsv1.2 -o /dev/null -w '%{http_code}' -m 5 "${HTTPS_URL}/")
[ "$app_code" = "200" ] || { echo "FALLO: ${HTTPS_URL}/ devolvió ${app_code} (¿flutter-web alcanzable en la red interna?)"; exit 1; }

echo "OK: el 8080 redirige HTTP a HTTPS, exige TLS 1.2+ y sirve la app solo por HTTPS."
