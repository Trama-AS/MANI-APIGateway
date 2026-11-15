#!/usr/bin/env bash
set -euo pipefail

# Instalacion y actualizacion reproducible de la VM de Backups (10.43.98.197) - SCRUM-1666
# Debe ejecutarse con sudo o como root. No sobreescribe credenciales existentes en /etc/mani-backups.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-estudiante}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[ERROR] Ejecutar con sudo: sudo bash $0" >&2
  exit 1
fi

echo "[1/5] Verificando dependencias PostgreSQL 17 y prometheus-node-exporter..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl gnupg lsb-release ca-certificates jq rsync prometheus-node-exporter

if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
  install -d /usr/share/postgresql-common/pgdg
  curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  apt-get update -qq
fi
apt-get install -y -qq postgresql-client-17 postgresql-17

echo "[2/5] Configurando cluster aislado 17/drill en 127.0.0.1:5433..."
if pg_lsclusters -h | awk '{print $1"/"$2}' | grep -qx "17/main"; then
  pg_ctlcluster 17 main stop || true
  sed -i 's/^auto$/manual/' /etc/postgresql/17/main/start.conf || true
fi
if ! pg_lsclusters -h | awk '{print $1"/"$2}' | grep -qx "17/drill"; then
  pg_createcluster 17 drill --port=5433 --start-conf=auto
fi
sed -i "s/^#\?listen_addresses.*/listen_addresses = '127.0.0.1'/" /etc/postgresql/17/drill/postgresql.conf
sed -i "s/^#\?port.*/port = 5433/" /etc/postgresql/17/drill/postgresql.conf
cat > /etc/postgresql/17/drill/pg_hba.conf <<'EOF'
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
EOF
chown postgres:postgres /etc/postgresql/17/drill/pg_hba.conf /etc/postgresql/17/drill/postgresql.conf
chmod 0640 /etc/postgresql/17/drill/pg_hba.conf
systemctl daemon-reload
pg_ctlcluster 17 drill restart

echo "[3/5] Configurando node_exporter con textfile collector..."
mkdir -p /var/lib/node_exporter/textfile_collector
chown -R "$TARGET_USER:$TARGET_USER" /var/lib/node_exporter/textfile_collector
chmod 0755 /var/lib/node_exporter /var/lib/node_exporter/textfile_collector
cat > /etc/default/prometheus-node-exporter <<'EOF'
ARGS="--collector.textfile.directory=/var/lib/node_exporter/textfile_collector"
EOF
systemctl enable --now prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "[4/5] Desplegando scripts y estructura de directorios..."
mkdir -p /opt/mani-backups/bin /opt/database-backups/mani/{daily/qa,daily/prod,weekly/qa,weekly/prod,drills,logs} /etc/mani-backups
cp "$SCRIPT_DIR/backup_databases.sh" "$SCRIPT_DIR/restore_drill.sh" "$SCRIPT_DIR/bootstrap_supabase_compat.sql" /opt/mani-backups/bin/
chmod 0750 /opt/mani-backups/bin/backup_databases.sh /opt/mani-backups/bin/restore_drill.sh
chmod 0644 /opt/mani-backups/bin/bootstrap_supabase_compat.sql
chown -R "$TARGET_USER:$TARGET_USER" /opt/mani-backups /opt/database-backups/mani /etc/mani-backups
chmod 0700 /etc/mani-backups

if [[ ! -f /etc/mani-backups/backup.passphrase ]]; then
  openssl rand -base64 48 > /etc/mani-backups/backup.passphrase
  chown "$TARGET_USER:$TARGET_USER" /etc/mani-backups/backup.passphrase
  chmod 0400 /etc/mani-backups/backup.passphrase
fi

if [[ ! -f /etc/mani-backups/.env.backups ]]; then
  cp "$SCRIPT_DIR/.env.backups.example" /etc/mani-backups/.env.backups
  chown "$TARGET_USER:$TARGET_USER" /etc/mani-backups/.env.backups
  chmod 0600 /etc/mani-backups/.env.backups
  echo "[AVISO] Completar QA_DATABASE_URL y PROD_DATABASE_URL en /etc/mani-backups/.env.backups"
fi

echo "[5/5] Activando unidades systemd..."
cp "$SCRIPT_DIR/systemd/mani-backup.service" /etc/systemd/system/mani-backup.service
cp "$SCRIPT_DIR/systemd/mani-backup.timer" /etc/systemd/system/mani-backup.timer
systemctl daemon-reload
systemctl enable --now mani-backup.timer
systemctl list-timers mani-backup.timer --no-pager
