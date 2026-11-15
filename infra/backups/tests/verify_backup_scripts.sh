#!/usr/bin/env bash
set -euo pipefail

# Pruebas offline y de sintaxis para scripts de respaldo y restauracion (SCRUM-1666)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[1/3] Validando sintaxis bash..."
bash -n \
  "$BACKUPS_DIR/backup_databases.sh" \
  "$BACKUPS_DIR/restore_drill.sh" \
  "$BACKUPS_DIR/install_backup_host.sh" \
  "$BACKUPS_DIR/tests/verify_backup_scripts.sh"

echo "[2/3] Verificando que no existan secretos reales en infra/backups/..."
if grep -rnE '(postgresql://[^<]+:[^<@]+@|SUPABASE_SERVICE_ROLE_KEY=|eyJhbGciOi)' "$BACKUPS_DIR" \
    --exclude=".env.backups.example" \
    --exclude="verify_backup_scripts.sh"; then
  echo "[ERROR] Posible secreto detectado en infra/backups/" >&2
  exit 1
fi

echo "[3/3] Probando ciclo de cifrado AES-256-CBC + SHA-256 + descifrado..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

openssl rand -base64 32 > "$TMP_DIR/key"
printf 'SELECT 1 AS mani_backup_test;\n' > "$TMP_DIR/sample.pgdump"
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -in "$TMP_DIR/sample.pgdump" -out "$TMP_DIR/sample.pgdump.enc" -pass "file:$TMP_DIR/key"
(cd "$TMP_DIR" && sha256sum sample.pgdump.enc > sample.pgdump.enc.sha256)
(cd "$TMP_DIR" && sha256sum -c sample.pgdump.enc.sha256)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in "$TMP_DIR/sample.pgdump.enc" -out "$TMP_DIR/sample.restored.pgdump" -pass "file:$TMP_DIR/key"
cmp -s "$TMP_DIR/sample.pgdump" "$TMP_DIR/sample.restored.pgdump"

echo "OK: Todas las validaciones de scripts de respaldo pasaron."
