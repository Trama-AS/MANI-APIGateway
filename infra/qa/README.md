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
