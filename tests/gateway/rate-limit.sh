#!/usr/bin/env bash
# Verifica el rate limiting (limit_req) en el Gateway NGINX (SCRUM-1655 / T-18 / QAS-14)
# Uso: tests/gateway/rate-limit.sh [baseUrl]   (por defecto http://localhost)
set -u
BASE="${1:-http://localhost}"
fallos=0

echo "=== 1. Trafico nominal de lectura no se ve afectado ==="
health_code=$(curl -s -k -L -o /dev/null -w '%{http_code}' "$BASE/health")
if [ "$health_code" = "200" ]; then
  echo "ok    GET /health -> $health_code"
else
  echo "FALLA GET /health -> $health_code (esperado 200)"
  fallos=$((fallos + 1))
fi

echo "=== 2. Rafaga en login (/api/v1/core/auth/login) supera burst=20 y responde 429 ==="
login_429=0
login_body=""
for i in $(seq 1 30); do
  resp=$(curl -s -k -L -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d '{"email":"ratelimit@test.local","password":"invalid"}' \
    "$BASE/api/v1/core/auth/login")
  code="${resp##*$'\n'}"
  if [ "$code" = "429" ]; then
    login_429=$((login_429 + 1))
    if [ -z "$login_body" ]; then
      login_body="${resp%$'\n'*}"
    fi
  fi
done

if [ "$login_429" -gt 0 ]; then
  echo "ok    Rafaga de 30 POST /api/v1/core/auth/login -> $login_429 respuestas 429"
else
  echo "FALLA Rafaga de 30 POST /api/v1/core/auth/login no devolvio ningun 429"
  fallos=$((fallos + 1))
fi

if echo "$login_body" | grep -q '"error":"TOO_MANY_REQUESTS"'; then
  echo "ok    Cuerpo 429 contiene error TOO_MANY_REQUESTS"
else
  echo "FALLA Cuerpo 429 inesperado: $login_body"
  fallos=$((fallos + 1))
fi

echo "=== 3. Rafaga de escritura (POST /api/v1/core/solicitudes) supera burst=40 y responde 429 ==="
write_429=0
for i in $(seq 1 50); do
  code=$(curl -s -k -L -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d '{}' "$BASE/api/v1/core/solicitudes")
  if [ "$code" = "429" ]; then
    write_429=$((write_429 + 1))
  fi
done

if [ "$write_429" -gt 0 ]; then
  echo "ok    Rafaga de 50 POST /api/v1/core/solicitudes -> $write_429 respuestas 429"
else
  echo "FALLA Rafaga de 50 POST /api/v1/core/solicitudes no devolvio ningun 429"
  fallos=$((fallos + 1))
fi

echo "=== 4. Trafico nominal de lectura tras rafaga sigue sin recibir 429 ==="
for i in $(seq 1 5); do
  read_code=$(curl -s -k -L -o /dev/null -w '%{http_code}' "$BASE/api/v1/core/catalog")
  if [ "$read_code" = "429" ]; then
    echo "FALLA GET /api/v1/core/catalog devolvio 429 tras rafaga de escritura"
    fallos=$((fallos + 1))
    break
  fi
done
echo "ok    GET /api/v1/core/catalog sin afectacion tras rafaga (ultimo codigo: $read_code)"

if [ "$fallos" -gt 0 ]; then
  echo "ERROR: $fallos verificaciones fallaron"
  exit 1
fi
echo "EXITO: Rate limiting (login_limit y write_limit) verificado correctamente"
