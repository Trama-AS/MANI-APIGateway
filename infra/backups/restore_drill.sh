#!/usr/bin/env bash
set -euo pipefail

# Simulacro cronometrado de restauracion en instancia PostgreSQL 17 aislada (SCRUM-1666 / QAS-17)
# Nunca toca las bases compartidas de QA ni PROD en Supabase.
# Uso: restore_drill.sh [--env qa|prod] [--artifact /ruta/archivo.pgdump.enc] [--keep-db]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/etc/mani-backups/.env.backups}"
COMPAT_SQL="${COMPAT_SQL:-$SCRIPT_DIR/bootstrap_supabase_compat.sql}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$CONFIG_FILE"
  set +a
fi

TARGET_ENV="qa"
ARTIFACT_PATH=""
KEEP_DB=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      TARGET_ENV="$2"
      shift 2
      ;;
    --artifact)
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --keep-db)
      KEEP_DB=1
      shift
      ;;
    *)
      echo "Uso: $0 [--env qa|prod] [--artifact <ruta.pgdump.enc>] [--keep-db]" >&2
      exit 1
      ;;
  esac
done

BACKUP_ROOT="${BACKUP_ROOT:-/opt/database-backups/mani}"
BACKUP_ENCRYPTION_KEY_FILE="${BACKUP_ENCRYPTION_KEY_FILE:-/etc/mani-backups/backup.passphrase}"
DRILL_PG_HOST="${DRILL_PG_HOST:-127.0.0.1}"
DRILL_PG_PORT="${DRILL_PG_PORT:-5433}"
DRILL_PG_USER="${DRILL_PG_USER:-postgres}"
RTO_TARGET_SECONDS="${RTO_TARGET_SECONDS:-1800}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"

for bin in psql pg_restore openssl sha256sum date find; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERROR] Herramienta requerida no instalada: $bin" >&2
    exit 1
  fi
done

if [[ -z "$ARTIFACT_PATH" ]]; then
  ARTIFACT_PATH="$(find "$BACKUP_ROOT/daily/$TARGET_ENV" -maxdepth 1 -type f -name '*.pgdump.enc' | sort -r | head -n 1)"
fi

if [[ -z "$ARTIFACT_PATH" || ! -f "$ARTIFACT_PATH" ]]; then
  echo "[ERROR] No se encontro artefacto .pgdump.enc para ambiente '$TARGET_ENV' en $BACKUP_ROOT/daily/$TARGET_ENV" >&2
  exit 1
fi

SHA_FILE="${ARTIFACT_PATH}.sha256"
if [[ ! -f "$SHA_FILE" ]]; then
  echo "[ERROR] Falta archivo de checksum: $SHA_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_ROOT/drills" "$BACKUP_ROOT/logs"
TS_UTC="$(date -u +%Y%m%dT%H%M%SZ)"
DRILL_DB="mani_restore_drill_${TARGET_ENV}_${TS_UTC,,}"
DRILL_LOG="$BACKUP_ROOT/logs/drill_${TARGET_ENV}_${TS_UTC}.log"

TMP_WORK_DIR="$(mktemp -d /tmp/mani-restore-drill-XXXXXX)"
PLAIN_DUMP="$TMP_WORK_DIR/restore.pgdump"

cleanup() {
  rm -rf "$TMP_WORK_DIR"
  if [[ "$KEEP_DB" -eq 0 ]]; then
    psql -h "$DRILL_PG_HOST" -p "$DRILL_PG_PORT" -U "$DRILL_PG_USER" -d postgres -v ON_ERROR_STOP=0 \
      -c "DROP DATABASE IF EXISTS \"$DRILL_DB\" WITH (FORCE);" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

START_EPOCH="$(date +%s)"
echo "=== SIMULACRO DE RESTAURACION CRONOMETRADO ($TARGET_ENV) — $TS_UTC ===" | tee "$DRILL_LOG"
echo "Artefacto: $(basename "$ARTIFACT_PATH")" | tee -a "$DRILL_LOG"
echo "Destino aislado: $DRILL_PG_HOST:$DRILL_PG_PORT / DB: $DRILL_DB" | tee -a "$DRILL_LOG"

echo "[1/5] Verificando integridad SHA-256..." | tee -a "$DRILL_LOG"
(cd "$(dirname "$ARTIFACT_PATH")" && sha256sum -c "$(basename "$SHA_FILE")") | tee -a "$DRILL_LOG"

echo "[2/5] Descifrando volcado AES-256-CBC..." | tee -a "$DRILL_LOG"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in "$ARTIFACT_PATH" \
  -out "$PLAIN_DUMP" \
  -pass "file:$BACKUP_ENCRYPTION_KEY_FILE"
chmod 0600 "$PLAIN_DUMP"

echo "[3/5] Creando base aislada y compatibilidad Supabase..." | tee -a "$DRILL_LOG"
psql -h "$DRILL_PG_HOST" -p "$DRILL_PG_PORT" -U "$DRILL_PG_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE \"$DRILL_DB\";" >>"$DRILL_LOG" 2>&1
psql -h "$DRILL_PG_HOST" -p "$DRILL_PG_PORT" -U "$DRILL_PG_USER" -d "$DRILL_DB" -v ON_ERROR_STOP=1 \
  -f "$COMPAT_SQL" >>"$DRILL_LOG" 2>&1

echo "[4/5] Ejecutando pg_restore en base aislada..." | tee -a "$DRILL_LOG"
RESTORE_START="$(date +%s)"
TOC_LIST="$TMP_WORK_DIR/restore.toc"
# Evita colision con el esquema 'public' preexistente manteniendo --exit-on-error estricto
pg_restore --list "$PLAIN_DUMP" | grep -vE '^[0-9]+; [0-9]+ [0-9]+ SCHEMA - public ' > "$TOC_LIST"
pg_restore \
  --host="$DRILL_PG_HOST" \
  --port="$DRILL_PG_PORT" \
  --username="$DRILL_PG_USER" \
  --dbname="$DRILL_DB" \
  --use-list="$TOC_LIST" \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  "$PLAIN_DUMP" >>"$DRILL_LOG" 2>&1
RESTORE_END="$(date +%s)"
RESTORE_SECONDS=$(( RESTORE_END - RESTORE_START ))

echo "[5/5] Validando tablas, politicas RLS y conteos de filas..." | tee -a "$DRILL_LOG"
VERIFY_OUT="$(psql -h "$DRILL_PG_HOST" -p "$DRILL_PG_PORT" -U "$DRILL_PG_USER" -d "$DRILL_DB" -At -F'|' -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'public_tables', count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';
SELECT 'rls_enabled_tables', count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity=true;
SELECT 'tenant_rows', count(*) FROM public.tenant;
SELECT 'usuario_rows', count(*) FROM public.usuario;
SELECT 'aliado_rows', count(*) FROM public.aliado;
SELECT 'cliente_rows', count(*) FROM public.cliente;
SELECT 'categoria_servicio_rows', count(*) FROM public.categoria_servicio;
SELECT 'solicitud_rows', count(*) FROM public.solicitud;
SELECT 'schema_migrations_rows', count(*) FROM public.schema_migrations;
SQL
)"
echo "$VERIFY_OUT" | tee -a "$DRILL_LOG"

PUBLIC_TABLES="$(echo "$VERIFY_OUT" | awk -F'|' '$1=="public_tables"{print $2}')"
if [[ -z "$PUBLIC_TABLES" || "$PUBLIC_TABLES" -lt 30 ]]; then
  echo "[ERROR] Conteo de tablas public restauradas insuficiente: ${PUBLIC_TABLES:-0}" | tee -a "$DRILL_LOG" >&2
  exit 1
fi

END_EPOCH="$(date +%s)"
TOTAL_RTO_SECONDS=$(( END_EPOCH - START_EPOCH ))

RTO_RESULT="PASS"
if (( TOTAL_RTO_SECONDS > RTO_TARGET_SECONDS )); then
  RTO_RESULT="FAIL"
fi

SUMMARY_FILE="$BACKUP_ROOT/drills/last_drill_${TARGET_ENV}.json"
cat > "$SUMMARY_FILE" <<EOF
{
  "env": "$TARGET_ENV",
  "timestamp_utc": "$TS_UTC",
  "artifact": "$(basename "$ARTIFACT_PATH")",
  "isolated_db": "$DRILL_DB",
  "pg_restore_seconds": $RESTORE_SECONDS,
  "total_rto_seconds": $TOTAL_RTO_SECONDS,
  "rto_target_seconds": $RTO_TARGET_SECONDS,
  "rto_status": "$RTO_RESULT",
  "public_tables": $PUBLIC_TABLES
}
EOF

if [[ -d "$TEXTFILE_DIR" ]]; then
  DRILL_PROM="$TEXTFILE_DIR/mani_backup_drill.prom"
  PASS_INT=$([[ "$RTO_RESULT" == "PASS" ]] && echo 1 || echo 0)
  {
    echo "# HELP mani_backup_last_drill_timestamp_seconds Epoch UTC del ultimo simulacro de restauracion"
    echo "# TYPE mani_backup_last_drill_timestamp_seconds gauge"
    if [[ -f "$DRILL_PROM" ]]; then
      grep "^mani_backup_last_drill_timestamp_seconds{" "$DRILL_PROM" | grep -v "env=\"$TARGET_ENV\"" || true
    fi
    echo "mani_backup_last_drill_timestamp_seconds{env=\"$TARGET_ENV\"} $END_EPOCH"
    echo "# HELP mani_backup_last_drill_rto_seconds Tiempo total RTO medido en segundos"
    echo "# TYPE mani_backup_last_drill_rto_seconds gauge"
    if [[ -f "$DRILL_PROM" ]]; then
      grep "^mani_backup_last_drill_rto_seconds{" "$DRILL_PROM" | grep -v "env=\"$TARGET_ENV\"" || true
    fi
    echo "mani_backup_last_drill_rto_seconds{env=\"$TARGET_ENV\"} $TOTAL_RTO_SECONDS"
    echo "# HELP mani_backup_last_drill_status Resultado del ultimo simulacro (1=PASS, 0=FAIL)"
    echo "# TYPE mani_backup_last_drill_status gauge"
    if [[ -f "$DRILL_PROM" ]]; then
      grep "^mani_backup_last_drill_status{" "$DRILL_PROM" | grep -v "env=\"$TARGET_ENV\"" || true
    fi
    echo "mani_backup_last_drill_status{env=\"$TARGET_ENV\"} $PASS_INT"
  } > "${DRILL_PROM}.tmp"
  chmod 0644 "${DRILL_PROM}.tmp"
  mv "${DRILL_PROM}.tmp" "$DRILL_PROM"
fi

echo "------------------------------------------------------------" | tee -a "$DRILL_LOG"
echo "RESULTADO SIMULACRO ($TARGET_ENV): $RTO_RESULT" | tee -a "$DRILL_LOG"
echo "Tiempo pg_restore: ${RESTORE_SECONDS}s | RTO total medido: ${TOTAL_RTO_SECONDS}s (objetivo <= ${RTO_TARGET_SECONDS}s)" | tee -a "$DRILL_LOG"

[[ "$RTO_RESULT" == "PASS" ]]
