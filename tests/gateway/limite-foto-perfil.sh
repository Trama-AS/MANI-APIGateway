#!/usr/bin/env bash
# Verifica los límites de client_max_body_size en el Gateway (TEC-23 / SCRUM-1389)
# C1: 4 MB en /api/v1/core/profiles/me/photo no devuelve 413.
# C2: 7 MB en /api/v1/core/profiles/me/photo devuelve 413; otras rutas mantienen el límite de 1 MB (2 MB devuelve 413).
# Uso: tests/gateway/limite-foto-perfil.sh [baseUrl]   (por defecto http://localhost)
set -u
BASE="${1:-http://localhost}"
fallos=0

TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'gw_test')
trap 'rm -rf "$TMP_DIR"' EXIT

PAYLOAD_4M="$TMP_DIR/payload_4m.bin"
PAYLOAD_7M="$TMP_DIR/payload_7m.bin"
PAYLOAD_2M="$TMP_DIR/payload_2m.bin"
PAYLOAD_500K="$TMP_DIR/payload_500k.bin"

# Crear archivos de prueba
dd if=/dev/zero of="$PAYLOAD_4M" bs=1048576 count=4 2>/dev/null || head -c 4194304 /dev/zero > "$PAYLOAD_4M"
dd if=/dev/zero of="$PAYLOAD_7M" bs=1048576 count=7 2>/dev/null || head -c 7340032 /dev/zero > "$PAYLOAD_7M"
dd if=/dev/zero of="$PAYLOAD_2M" bs=1048576 count=2 2>/dev/null || head -c 2097152 /dev/zero > "$PAYLOAD_2M"
dd if=/dev/zero of="$PAYLOAD_500K" bs=1024 count=500 2>/dev/null || head -c 512000 /dev/zero > "$PAYLOAD_500K"

esperar_distinto() {
  local descripcion="$1" no_esperado="$2" obtenido
  shift 2
  obtenido=$(curl -s -k -L -o /dev/null -w '%{http_code}' "$@")
  if [ "$obtenido" != "$no_esperado" ]; then
    echo "ok    $descripcion -> $obtenido (distinto de $no_esperado, paso perimetro)"
  else
    echo "FALLA $descripcion -> $obtenido (se esperaba distinto de $no_esperado)"
    fallos=$((fallos + 1))
  fi
}

esperar_igual() {
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

echo "=== Verificando Criterio C1: 4 MB en foto de perfil pasa el Gateway ==="
esperar_igual "POST /profiles/me/photo con 4 MB sin token responde 401 (no 500 ni 413)" 401 \
  -X POST -F "photo=@$PAYLOAD_4M;type=image/png" "$BASE/api/v1/core/profiles/me/photo"

esperar_igual "POST /profiles/me/photo/ (con barra) con 4 MB sin token responde 401 (no 500 ni 413)" 401 \
  -X POST -F "photo=@$PAYLOAD_4M;type=image/png" "$BASE/api/v1/core/profiles/me/photo/"

echo "=== Verificando Criterio C2: > 6 MB en foto de perfil es rechazada con 413 ==="
esperar_igual "POST /profiles/me/photo con 7 MB es rechazada con 413" 413 \
  -X POST -F "photo=@$PAYLOAD_7M;type=image/png" "$BASE/api/v1/core/profiles/me/photo"

echo "=== Verificando Criterio C2 (Aislamiento): demas rutas mantienen limite de 1 MB ==="
esperar_igual "PATCH /profiles/me con 2 MB es rechazada con 413" 413 \
  -X PATCH -H 'Content-Type: application/json' --data-binary "@$PAYLOAD_2M" "$BASE/api/v1/core/profiles/me"

esperar_distinto "PATCH /profiles/me con 500 KB pasa sin 413" 413 \
  -X PATCH -H 'Content-Type: application/json' --data-binary "@$PAYLOAD_500K" "$BASE/api/v1/core/profiles/me"

if [ "$fallos" -gt 0 ]; then
  echo "ERROR: $fallos verificaciones fallaron"
  exit 1
fi
echo "EXITO: Criterios C1 y C2 verificados correctamente para client_max_body_size"
