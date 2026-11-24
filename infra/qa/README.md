# Infraestructura QA — MANI (`SCRUM-1672` / T-35)

Versionado oficial de `/opt/mani/docker-compose.qa.yml` para la VM de QA (`10.43.100.141`, 4 vCPU / ~11.6 GiB RAM), separada del stack de monitoreo (`monitoring/`, ejecutado en Calidad `10.43.98.196`).

## Límites de CPU y memoria (`deploy.resources`)

| Servicio | Contenedor | Límite CPU | Límite RAM | Reserva CPU | Reserva RAM |
|---|---|---:|---:|---:|---:|
| `gateway` | `mani-api-gateway` | `0.50` | `128M` | `0.10` | `32M` |
| `core-service` | `mani-core-service` | `1.00` | `512M` | `0.25` | `128M` |
| `rules-service` | `mani-rules-service` | `1.00` | `768M` | `0.25` | `256M` |
| `dispatch-service` | `mani-dispatch-service` | `1.00` | `512M` | `0.25` | `128M` |
| `flutter-web` | `mani-flutter-web` | `0.25` | `128M` | `0.05` | `32M` |
| `landing-web` | `mani-landing-web` | `0.25` | `128M` | `0.05` | `32M` |
| `kafka` | `mani-kafka` | `1.00` | `1024M` | `0.25` | `384M` |

- Suma de techos de memoria: `3200M` (~`3.13 GiB`), acotando la contención sobre la VM compartida.
- Reserva mínima agregada: `1.20` vCPU y `992M` RAM.

## Despliegue, scripts cronometrados (`SCRUM-1674`, `SCRUM-1675`) y verificación en QA

Los secretos reales viven únicamente en `/opt/mani/.env.qa` en la VM (nunca en este repositorio).

| Script | Propósito | Objetivo de tiempo |
|---|---|---:|
| `desplegar_release_qa.sh` | Descarga `:staging`, registra digests previos, recrea Compose QA y valida 6 endpoints `200 OK` | `≤ 10 min` (`600s`) |
| `rollback_qa.sh` | Aplica override temporal por digest sobre un servicio, recrea con `--no-deps` y valida `check-qa.sh` | `≤ 5 min` (`300s`) |

```bash
cd /opt/mani
# Despliegue completo cronometrado de :staging
bash desplegar_release_qa.sh

# Rollback cronometrado por digest previo de un servicio
bash rollback_qa.sh gateway ghcr.io/trama-as/mani-apigateway@sha256:<DIGEST_ANTERIOR>

# Verificación de límites y salud
/opt/mani/check-qa.sh
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'
docker inspect --format '{{.Name}} mem={{.HostConfig.Memory}} nanocpus={{.HostConfig.NanoCpus}}' \
  mani-api-gateway mani-core-service mani-rules-service mani-dispatch-service mani-flutter-web mani-landing-web mani-kafka
```

## Puerto 8080 solo por HTTPS (`SCRUM-1718` / `QAS-43`)

Desde fuera de la VM solo responde el 8080 (80 y 443 no pasan la red). Antes lo publicaba `mani-flutter-web` por HTTP,
así que la app y la API (`/api/` va por el proxy interno de flutter-web) viajaban sin cifrar. Ahora:

- El **Gateway** publica `8080:8080` y lo atiende con TLS 1.2+ (mismo certificado que el 443) en un `server` aparte de
  `nginx.conf`, que reenvía todo a `flutter-web:80` por `mani-network`.
- `flutter-web` ya no publica puertos (`expose: 80`) y su `API_GATEWAY_URL` pasa a `https://10.43.100.141:8080`.
- HTTP plano al 8080 recibe `301` a `https://<host>:8080/...`. El tráfico interno (Core → `gateway:80`, flutter-web →
  `mani-api-gateway:80`) no pasa por el 8080 del host y no cambia.
- El certificado es autofirmado: el navegador pide aceptarlo una vez, y `curl` necesita `-k`.

Verificación tras desplegar:

```bash
curl -sI http://10.43.100.141:8080/          # 301, Location: https://10.43.100.141:8080/
curl -skI https://10.43.100.141:8080/        # 200, Strict-Transport-Security
bash tests/gateway/puerto-8080-https.sh 10.43.100.141
```

Al desplegar este cambio hay que copiar también el `docker-compose.qa.yml` nuevo a `/opt/mani` (la imagen del Gateway
sola no basta: si flutter-web sigue publicando el 8080, el Gateway no puede tomarlo). La variable de repositorio
`QA_FLUTTER_URL` del workflow de regresión pasa a `https://10.43.100.141:8080`.

## Exporters y Promtail en QA (`SCRUM-1671`, `SCRUM-1676` / `ADR-0038`)

Para evitar conflictos con `--remove-orphans` de `desplegar_release_qa.sh`, los exporters ligeros y el agente de logs viven en `docker-compose.exporters.yml` (`name: mani-qa-exporters`), compartiendo la red `mani-network` y el volumen `mani-nginx-metrics-logs`:

| Servicio | Contenedor | Puerto | Rol |
|---|---|---:|---|
| `node-exporter` | `mani-qa-node-exporter` | `9100` | CPU, RAM, disco y red de la VM QA |
| `cadvisor` | `mani-qa-cadvisor` | `8081` | Consumo CPU/RAM por contenedor Docker (`v0.55.1` con socket de containerd desde `SCRUM-1670`; `v0.49.1` solo exportaba la serie del host con Docker 29) |
| `postgres-exporter` | `mani-qa-postgres-exporter` | `9187` | Conexiones activas y estadísticas PostgreSQL (`DATABASE_URL` de `.env.qa`) |
| `nginx-exporter` | `mani-qa-nginx-exporter` | `9113` | Métricas de conexiones NGINX (`/nginx_status`) |
| `nginxlog-exporter` | `mani-qa-nginxlog-exporter` | `4040` | Códigos HTTP (`401`, `403`, `429`, `5xx`) y latencia (`$request_time`, histograma) por servicio (`route`) desde `/var/log/nginx-metrics/metrics.log` |
| `promtail` | `mani-qa-promtail` | `9080` | Recolección de logs Docker hacia Loki en Calidad (`10.43.98.196:3100`) |

```bash
cd /opt/mani
docker compose -f docker-compose.exporters.yml --env-file .env.qa up -d
```

Tras `SCRUM-1670`, actualizar `cadvisor` y `nginxlog-exporter` **después** de que QA corra el Gateway `:staging` con el nuevo `metrics_kv`:

```bash
cd /opt/mani
cp <clon>/infra/qa/docker-compose.exporters.yml <clon>/infra/qa/nginxlog-exporter.hcl .
docker compose -f docker-compose.exporters.yml --env-file .env.qa up -d cadvisor nginxlog-exporter
curl -s localhost:8081/metrics | grep 'container_cpu_usage_seconds_total{' | grep -o 'name="mani-[^"]*"' | sort -u
curl -s localhost:4040/metrics | grep nginx_http_response_count_total | grep -o 'route="[^"]*"' | sort -u
```
