# Stack de Monitoreo — MANI (`SCRUM-1667` / T-30 y `SCRUM-1668` / T-31)

Stack versionado de observabilidad para QA (`10.43.100.141`), ejecutado en la VM de **Calidad (`10.43.98.196`)** en `/home/estudiante/monitoreo/` mediante Docker Compose (separado del Compose de aplicación en QA).

## Componentes incluidos

| Archivo / Carpeta | Rol | Contenedor / Puerto |
|---|---|---|
| `docker-compose.yml` | Orquestación de Prometheus (`35d`), Blackbox, Alertmanager, Mailpit, Loki (`840h`) y Grafana | `mani-mon-*` (`9090`, `9115`, `9093`, `8025`/`1025`, `3100`, `3000`) |
| `prometheus/prometheus.yml` | Scrape QA HTTPS (`mani_core_qa`, `mani_salud_qa`), Exporters QA (`9100`, `8081`, `9187`, `9113`, `4040`), PROD (`mani_core_prod`, `mani_salud_prod`) y VM Backups (`10.43.98.197:9100`) | `mani-mon-prometheus` (`prom/prometheus:v2.53.0`) |
| `prometheus/auth-alerts.yml` | Reglas de alerta `HighAuth401Rate` y `IncompleteClaimsAttemptsDetected` | Cargado vía `rule_files` |
| `prometheus/sla-alerts.yml` | Reglas SLA QA/PROD y respaldos (`SCRUM-1666`): `ServiceDown` (`2m`), `High5xxRate` (`>1%`), `HighLatencyP95` (`>0.5s`), `HighCpuUsage` (`>70%`), `BackupFailed`, `BackupStale`, `BackupOffsiteSyncFailed` | Cargado vía `rule_files` |
| `alertmanager/alertmanager.yml` | Enrutamiento de alertas hacia canal SMTP `Mailpit` (`send_resolved: true`) | `mani-mon-alertmanager` (`prom/alertmanager:v0.27.0`) |
| `loki/loki-config.yml` | Almacenamiento centralizado TSDB `v13` de logs con retención `840h` (`35d`) (`ADR-0038`) | `mani-mon-loki` (`grafana/loki:3.1.1`) |
| `blackbox/blackbox.yml` | Sonda `http_2xx` con timeout `10s`, `follow_redirects: true` y soporte TLS | `mani-mon-blackbox` (`prom/blackbox-exporter:v0.25.0`) |
| `grafana/datasources/` | Provisionamiento automático de `Prometheus` y `Loki` (`uid: loki`) | `mani-mon-grafana` (`grafana/grafana:11.1.0`) |
| `grafana/provisioning/dashboards/dashboards.yml` | Provisionamiento automático de dashboards | `mani-mon-grafana` |
| `grafana/dashboards/` | `mani-qa-salud.json` (QA salud) + `mani-prod-exporters-y-logs.json` (PROD, Exporters QA, Loki) | Auto-cargado al iniciar Grafana |
| `.env.example` | Plantilla de credenciales locales para `.env` (sin secretos reales) | — |

## Reconstrucción en una VM limpia

1. Clonar `MANI-APIGateway` y entrar a `monitoring/`:
   ```bash
   cd monitoring
   cp .env.example .env
   # Editar .env asignando una clave fuerte en GF_SECURITY_ADMIN_PASSWORD
   chmod 600 .env
   ```
2. Levantar el stack:
   ```bash
   docker compose up -d
   ```
3. Verificar estado, retención de `35d` y provisionamiento:
   ```bash
   docker compose ps
   curl -s http://127.0.0.1:9090/api/v1/status/flags | grep retention
   curl -s http://127.0.0.1:9090/api/v1/targets | grep -E '"health"|"scrapeUrl"'
   ```

## Retención de Prometheus (`SCRUM-1668`)

`prometheus` se ejecuta con:
- `--storage.tsdb.retention.time=35d`

Esto conserva 35 días de métricas (cubre un ciclo mensual completo más holgura de cierre de sprint y análisis histórico, frente al valor por defecto de `15d`).

## Ventanas de mantenimiento declaradas (Disponibilidad ≥ 99,9 %)

Para medir el objetivo de disponibilidad **≥ 99,9 %** sin distorsionar el presupuesto de error por despliegues o mantenimiento planificado:

| Concepto | Definición operativa |
|---|---|
| **Presupuesto de indisponibilidad no planificada (SLO 99,9 % / 30 días)** | Máximo **43,2 minutos/mes** (o `50,4 minutos` sobre la ventana de `35d` en Prometheus) de caída no planificada sobre los endpoints sondeados por `mani_salud_qa`. |
| **Ventana de mantenimiento ordinaria (QA y Calidad)** | **Domingos de 02:00 a 04:00 COT** (`UTC-5`) — despliegues mayores, recreación de contenedores o pruebas de restauración fuera de horario académico y de evaluación PO. |
| **Ventana de despliegue rápido (entre semana)** | **Lunes a sábado de 22:00 a 23:00 COT** únicamente con aviso previo al equipo y duración ≤ 5 minutos (`docker compose up -d`). |
| **Regla de cómputo en Prometheus (`probe_success`)** | Toda indisponibilidad ocurrida **fuera** de ventana declarada consume presupuesto de error (`SLO`). Las interrupciones anunciadas dentro de la ventana se documentan en bitácora de despliegue y se excluyen del cálculo mensual de disponibilidad operativa. |
