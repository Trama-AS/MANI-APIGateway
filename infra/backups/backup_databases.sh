#!/usr/bin/env bash
set -euo pipefail

# Respaldo automatico cifrado para bases PostgreSQL de MANI (SCRUM-1666 / T-29)
# - Ejecuta pg_dump en formato custom (-Fc) con compresion nivel 9
# - Cifra inmediatamente en reposo con OpenSSL AES-256-CBC + PBKDF2 (600 000 iter)
# - Genera SHA-256 del artefacto cifrado y metadatos sanitizados (sin credenciales)
# - Aplica retencion GFS (diario + semanal dominical)
# - Replica artefactos cifrados off-host via rsync/SSH (opcional)
# - Publica metricas atomicas para Prometheus node_exporter textfile collector

CONFIG_FILE="${CONFIG_FILE:-/etc/mani-backups/.env.backups}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[ERROR] No existe archivo de configuracion: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$CONFIG_FILE"
set +a

BACKUP_ENVS="${BACKUP_ENVS:-qa prod}"
BACKUP_SCHEMAS="${BACKUP_SCHEMAS:-public app}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/database-backups/mani}"
BACKUP_ENCRYPTION_KEY_FILE="${BACKUP_ENCRYPTION_KEY_FILE:-/etc/mani-backups/backup.passphrase}"
RETENTION_DAILY="${RETENTION_DAILY:-14}"
RETENTION_WEEKLY="${RETENTION_WEEKLY:-4}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
LOCK_FILE="${LOCK_FILE:-/tmp/mani_backup_databases.lock}"

for bin in pg_dump openssl sha256sum awk date find; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERROR] Herramienta requerida no instalada: $bin" >&2
    exit 1
  fi
done

if [[ ! -r "$BACKUP_ENCRYPTION_KEY_FILE" ]]; then
  echo "[ERROR] No es legible el archivo de llave de cifrado: $BACKUP_ENCRYPTION_KEY_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_ROOT/logs" "$BACKUP_ROOT/daily" "$BACKUP_ROOT/weekly"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[ERROR] Ya existe otra ejecucion activa de backup_databases.sh" >&2
  exit 1
fi

TMP_WORK_DIR="$(mktemp -d /tmp/mani-backup-XXXXXX)"
cleanup() {
  rm -rf "$TMP_WORK_DIR"
}
trap cleanup EXIT

PROM_TMP="$TMP_WORK_DIR/mani_backups.prom"
{
  echo "# HELP mani_backup_last_status Estado del ultimo respaldo (1=ok, 0=error)"
  echo "# TYPE mani_backup_last_status gauge"
  echo "# HELP mani_backup_last_success_timestamp_seconds Epoch UTC del ultimo respaldo exitoso"
  echo "# TYPE mani_backup_last_success_timestamp_seconds gauge"
  echo "# HELP mani_backup_last_attempt_timestamp_seconds Epoch UTC del ultimo intento de respaldo"
  echo "# TYPE mani_backup_last_attempt_timestamp_seconds gauge"
  echo "# HELP mani_backup_last_duration_seconds Duracion en segundos del ultimo respaldo"
  echo "# TYPE mani_backup_last_duration_seconds gauge"
  echo "# HELP mani_backup_last_size_bytes Tamano en bytes del archivo cifrado mas reciente"
  echo "# TYPE mani_backup_last_size_bytes gauge"
  echo "# HELP mani_backup_offsite_sync_status Estado de sincronizacion hacia almacenamiento externo (1=ok, 0=error)"
  echo "# TYPE mani_backup_offsite_sync_status gauge"
} > "$PROM_TMP"

# Preserva el ultimo timestamp de exito previo si existiera una corrida fallida para un ambiente
get_prev_success_ts() {
  local env_name="$1"
  local existing_prom="$TEXTFILE_DIR/mani_backups.prom"
  if [[ -f "$existing_prom" ]]; then
    awk -v env="$env_name" -F'[{} ="]+' '/^mani_backup_last_success_timestamp_seconds\{/ {
      for(i=1;i<=NF;i++) if($i=="env" && $(i+1)==env) print $NF
    }' "$existing_prom" | tail -n 1
  fi
}

build_schema_args() {
  local schemas_str="$1"
  local args=()
  for s in $schemas_str; do
    args+=("--schema=$s")
  done
  printf '%s\n' "${args[@]}"
}

prune_dir_keep_n() {
  local dir="$1"
  local keep="$2"
  local -a files=()
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name '*.pgdump.enc' | sort -r)
  if (( ${#files[@]} > keep )); then
    for old_enc in "${files[@]:keep}"; do
      local base="${old_enc%.pgdump.enc}"
      rm -f "$old_enc" "${old_enc}.sha256" "${base}.meta.json"
    done
  fi
}

OVERALL_RC=0
TS_UTC="$(date -u +%Y%m%dT%H%M%SZ)"
IS_SUNDAY="$(date -u +%u)"

for env_name in $BACKUP_ENVS; do
  ENV_UPPER="$(echo "$env_name" | tr '[:lower:]' '[:upper:]')"
  VAR_URL="${ENV_UPPER}_DATABASE_URL"
  DB_URL="${!VAR_URL:-}"

  ATTEMPT_TS="$(date +%s)"
  START_EPOCH="$ATTEMPT_TS"
  LOG_FILE="$BACKUP_ROOT/logs/${env_name}_${TS_UTC}.log"

  DAILY_DIR="$BACKUP_ROOT/daily/$env_name"
  WEEKLY_DIR="$BACKUP_ROOT/weekly/$env_name"
  mkdir -p "$DAILY_DIR" "$WEEKLY_DIR"

  if [[ -z "$DB_URL" ]]; then
    echo "[ERROR] Variable $VAR_URL vacia en $CONFIG_FILE" | tee -a "$LOG_FILE" >&2
    PREV_TS="$(get_prev_success_ts "$env_name")"
    echo "mani_backup_last_status{env=\"$env_name\"} 0" >> "$PROM_TMP"
    echo "mani_backup_last_attempt_timestamp_seconds{env=\"$env_name\"} $ATTEMPT_TS" >> "$PROM_TMP"
    echo "mani_backup_last_success_timestamp_seconds{env=\"$env_name\"} ${PREV_TS:-0}" >> "$PROM_TMP"
    echo "mani_backup_last_duration_seconds{env=\"$env_name\"} 0" >> "$PROM_TMP"
    echo "mani_backup_last_size_bytes{env=\"$env_name\"} 0" >> "$PROM_TMP"
    echo "mani_backup_offsite_sync_status{env=\"$env_name\"} 0" >> "$PROM_TMP"
    OVERALL_RC=1
    continue
  fi

  PLAIN_DUMP="$TMP_WORK_DIR/${env_name}_${TS_UTC}.pgdump"
  ENC_BASENAME="${env_name}_${TS_UTC}.pgdump.enc"
  ENC_PATH="$DAILY_DIR/$ENC_BASENAME"
  SHA_PATH="${ENC_PATH}.sha256"
  META_PATH="$DAILY_DIR/${env_name}_${TS_UTC}.meta.json"

  mapfile -t SCHEMA_FLAGS < <(build_schema_args "$BACKUP_SCHEMAS")

  echo "[$(date -u +%FT%TZ)] Iniciando respaldo de ambiente '$env_name' (esquemas: $BACKUP_SCHEMAS)" | tee -a "$LOG_FILE"
  if pg_dump "$DB_URL" \
      --format=custom \
      --compress=9 \
      --no-owner \
      --no-privileges \
      "${SCHEMA_FLAGS[@]}" \
      --file="$PLAIN_DUMP" 2>>"$LOG_FILE"; then

    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
      -in "$PLAIN_DUMP" \
      -out "$ENC_PATH" \
      -pass "file:$BACKUP_ENCRYPTION_KEY_FILE" 2>>"$LOG_FILE"
    chmod 0600 "$ENC_PATH"
    rm -f "$PLAIN_DUMP"

    (cd "$DAILY_DIR" && sha256sum "$ENC_BASENAME" > "${ENC_BASENAME}.sha256")
    chmod 0600 "$SHA_PATH"

    END_EPOCH="$(date +%s)"
    DURATION=$(( END_EPOCH - START_EPOCH ))
    ENC_BYTES="$(stat -c%s "$ENC_PATH")"
    ENC_SHA256="$(awk '{print $1}' "$SHA_PATH")"

    cat > "$META_PATH" <<EOF
{
  "env": "$env_name",
  "timestamp_utc": "$TS_UTC",
  "schemas": "$BACKUP_SCHEMAS",
  "cipher": "aes-256-cbc-pbkdf2-600000",
  "artifact": "$ENC_BASENAME",
  "size_bytes": $ENC_BYTES,
  "sha256": "$ENC_SHA256",
  "duration_seconds": $DURATION,
  "pg_dump_version": "$(pg_dump --version | head -n1)"
}
EOF
    chmod 0600 "$META_PATH"

    # Promocion semanal los domingos (o si aun no existe ningun respaldo semanal)
    WEEKLY_COUNT="$(find "$WEEKLY_DIR" -maxdepth 1 -type f -name '*.pgdump.enc' | wc -l)"
    if [[ "$IS_SUNDAY" == "7" || "$WEEKLY_COUNT" -eq 0 ]]; then
      cp -p "$ENC_PATH" "$WEEKLY_DIR/$ENC_BASENAME"
      cp -p "$SHA_PATH" "$WEEKLY_DIR/${ENC_BASENAME}.sha256"
      cp -p "$META_PATH" "$WEEKLY_DIR/${env_name}_${TS_UTC}.meta.json"
    fi

    prune_dir_keep_n "$DAILY_DIR" "$RETENTION_DAILY"
    prune_dir_keep_n "$WEEKLY_DIR" "$RETENTION_WEEKLY"

    # Sincronizacion off-host solo de archivos cifrados y metadatos
    OFFSITE_STATUS=1
    if [[ -n "${OFFSITE_RSYNC_TARGET:-}" ]]; then
      SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new"
      if [[ -n "${OFFSITE_SSH_KEY:-}" && -f "${OFFSITE_SSH_KEY:-}" ]]; then
        SSH_OPTS="-i $OFFSITE_SSH_KEY $SSH_OPTS"
      fi
      if rsync -az --delete \
          -e "ssh $SSH_OPTS" \
          --include="*/" \
          --include="*.pgdump.enc" \
          --include="*.sha256" \
          --include="*.meta.json" \
          --exclude="*" \
          "$BACKUP_ROOT/daily" "$BACKUP_ROOT/weekly" \
          "$OFFSITE_RSYNC_TARGET/" >>"$LOG_FILE" 2>&1; then
        OFFSITE_STATUS=1
        echo "[$(date -u +%FT%TZ)] Sincronizacion off-host completada ($OFFSITE_RSYNC_TARGET)" | tee -a "$LOG_FILE"
      else
        OFFSITE_STATUS=0
        OVERALL_RC=1
        echo "[ERROR] Fallo sincronizacion off-host hacia $OFFSITE_RSYNC_TARGET" | tee -a "$LOG_FILE" >&2
      fi
    fi

    echo "mani_backup_last_status{env=\"$env_name\"} 1" >> "$PROM_TMP"
    echo "mani_backup_last_attempt_timestamp_seconds{env=\"$env_name\"} $ATTEMPT_TS" >> "$PROM_TMP"
    echo "mani_backup_last_success_timestamp_seconds{env=\"$env_name\"} $END_EPOCH" >> "$PROM_TMP"
    echo "mani_backup_last_duration_seconds{env=\"$env_name\"} $DURATION" >> "$PROM_TMP"
    echo "mani_backup_last_size_bytes{env=\"$env_name\"} $ENC_BYTES" >> "$PROM_TMP"
    echo "mani_backup_offsite_sync_status{env=\"$env_name\"} $OFFSITE_STATUS" >> "$PROM_TMP"
    echo "[$(date -u +%FT%TZ)] Respaldo OK ($env_name): ${ENC_BYTES} bytes cifrados en ${DURATION}s" | tee -a "$LOG_FILE"
  else
    rm -f "$PLAIN_DUMP"
    END_EPOCH="$(date +%s)"
    DURATION=$(( END_EPOCH - START_EPOCH ))
    PREV_TS="$(get_prev_success_ts "$env_name")"
    echo "mani_backup_last_status{env=\"$env_name\"} 0" >> "$PROM_TMP"
    echo "mani_backup_last_attempt_timestamp_seconds{env=\"$env_name\"} $ATTEMPT_TS" >> "$PROM_TMP"
    echo "mani_backup_last_success_timestamp_seconds{env=\"$env_name\"} ${PREV_TS:-0}" >> "$PROM_TMP"
    echo "mani_backup_last_duration_seconds{env=\"$env_name\"} $DURATION" >> "$PROM_TMP"
    echo "mani_backup_last_size_bytes{env=\"$env_name\"} 0" >> "$PROM_TMP"
    echo "mani_backup_offsite_sync_status{env=\"$env_name\"} 0" >> "$PROM_TMP"
    echo "[ERROR] Fallo pg_dump para ambiente '$env_name' (ver $LOG_FILE)" | tee -a "$LOG_FILE" >&2
    OVERALL_RC=1
  fi
done

if [[ -d "$TEXTFILE_DIR" ]]; then
  cp "$PROM_TMP" "$TEXTFILE_DIR/mani_backups.prom.tmp"
  chmod 0644 "$TEXTFILE_DIR/mani_backups.prom.tmp"
  mv "$TEXTFILE_DIR/mani_backups.prom.tmp" "$TEXTFILE_DIR/mani_backups.prom"
fi

exit "$OVERALL_RC"
