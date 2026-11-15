# Respaldos Automáticos Cifrados y Simulacro de Restauración (`SCRUM-1666` / `T-29`)

Automatización de copias de seguridad lógicas (`pg_dump` 17) de las bases PostgreSQL de **QA** (`hpsxdotaizzclkeufzct`) y **PROD** (`tjxueukivwxsgipltqwb`), cifradas en reposo, replicadas fuera del host primario y verificadas mediante simulacro cronometrado de restauración en una instancia aislada.

> **Nota de confidencialidad:** Ningún volcado, cadena de conexión ni llave de cifrado se almacena en este repositorio. Las credenciales reales residen exclusivamente en `/etc/mani-backups/.env.backups` (`chmod 600`) y `/etc/mani-backups/backup.passphrase` (`chmod 400`) dentro de la VM de Backups (`10.43.98.197`).

## 1. Arquitectura Operativa

| Componente | Ubicación | Función |
|---|---|---|
| **Orquestador diario** | `10.43.98.197` (`systemd` `mani-backup.timer`) | Ejecución automática diaria a las `02:00 COT` (`07:00 UTC`) con `Persistent=true` |
| **Volcado y cifrado** | `/opt/mani-backups/bin/backup_databases.sh` | `pg_dump -Fc -Z9` → OpenSSL `AES-256-CBC` (`PBKDF2`, `600 000` iter) → `.pgdump.enc` + `.sha256` + `.meta.json` |
| **Custodia primaria** | `/opt/database-backups/mani/{daily,weekly}/{qa,prod}/` | Retención GFS: `14` copias diarias y `4` semanales dominicales por ambiente |
| **Copia externa off-host** | `10.43.98.196:/opt/database-backups-replica/mani/` | Réplica cifrada automática vía `rsync`/SSH (`ed25519`) sobre la VM de Calidad |
| **Base aislada de simulacro** | `10.43.98.197` (`127.0.0.1:5433`, PG `17/drill`) | Clúster PostgreSQL 17 independiente; nunca toca las bases compartidas de QA o PROD |
| **Simulacro cronometrado** | `/opt/mani-backups/bin/restore_drill.sh` | Descifra, valida `SHA-256`, restaura con `pg_restore`, verifica tablas/RLS/filas y mide `RTO` |
| **Observabilidad** | `node_exporter :9100` → Prometheus Calidad (`10.43.98.196`) | Exporta `mani_backup_*` y dispara alertas `BackupFailed`, `BackupStale` y `BackupOffsiteSyncFailed` |

## 2. Alcance frente a `QAS-17` y `SCRUM-1684`

- **RTO objetivo (`QAS-17`):** `≤ 30 min` (`1800 s`). Cumplido con holgura (`< 30 s` medidos en el simulacro para volcados de ~`18–21 MB`).
- **RPO con `pg_dump` diario:** `≤ 24 h` (corte diario `02:00 COT`). Alcanzar `RPO ≤ 5 min` (`QAS-17` provisional / [`SCRUM-1684`](https://maniservices.atlassian.net/browse/SCRUM-1684)) requiere WAL archiving continuo / PITR (plan pago Supabase Pro), brecha declarada explícitamente en [`04-respaldos-y-restauracion.md`](https://github.com/Trama-AS/MANI-docs/blob/main/wiki/08-infraestructura/04-respaldos-y-restauracion.md).

## 3. Comandos Operativos en `10.43.98.197`

```bash
# Instalación / actualización de scripts y timer systemd
sudo bash /opt/mani-backups/bin/install_backup_host.sh

# Verificar próxima ejecución automática
systemctl list-timers mani-backup.timer --no-pager

# Ejecutar respaldo manual inmediato de QA y PROD
sudo systemctl start mani-backup.service && sudo journalctl -u mani-backup.service -n 50 --no-pager

# Ejecutar simulacro cronometrado de restauración en base aislada (sin afectar QA compartida)
/opt/mani-backups/bin/restore_drill.sh --env qa
/opt/mani-backups/bin/restore_drill.sh --env prod
```
