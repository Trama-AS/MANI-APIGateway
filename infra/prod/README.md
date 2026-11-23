# Exporters de PROD — MANI (`SCRUM-1670`)

Exporters de la VM de PROD (`10.43.98.203`) que lee el Prometheus de Calidad (`10.43.98.196`). Van en un proyecto Compose propio (`mani-prod-exporters`), separado de `/opt/mani/docker-compose.prod.yml`, para que el despliegue de la aplicación no los borre.

| Servicio | Contenedor | Puerto | Para qué |
|---|---|---:|---|
| `node-exporter` | `mani-prod-node-exporter` | `9100` | CPU, memoria y disco de la VM |
| `cadvisor` | `mani-prod-cadvisor` | `8081` | CPU y memoria por contenedor (`name`) |
| `postgres-exporter` | `mani-prod-postgres-exporter` | `9187` | Conexiones a la base de PROD |
| `nginxlog-exporter` | `mani-prod-nginxlog-exporter` | `4040` | Peticiones, códigos (`401`/`403`/`429`/`5xx`) y latencia p95 por servicio, leídos del log del Gateway |

## Despliegue (DevOps)

Requisito: el Gateway de PROD debe correr una imagen `:latest` que ya incluya el `log_format metrics_kv` con `$request_time` (este PR promovido a `main`). Con una imagen anterior, `nginxlog-exporter` no reconoce las líneas y los paneles de tráfico quedan vacíos.

1. **Copiar los archivos** a la VM:
   ```bash
   sudo mkdir -p /opt/mani/exporters
   sudo cp infra/prod/docker-compose.exporters.yml infra/prod/nginxlog-exporter.hcl /opt/mani/exporters/
   ```
2. **Montar el log de métricas del Gateway** en `/opt/mani/docker-compose.prod.yml` (igual que en QA):
   ```yaml
   services:
     gateway:
       volumes:
         - nginx-metrics-logs:/var/log/nginx-metrics
   volumes:
     nginx-metrics-logs:
       name: mani-nginx-metrics-logs
   ```
   y recrear solo el Gateway, dentro de la ventana de despliegue rápido (22:00–23:00 COT):
   ```bash
   cd /opt/mani && docker compose -f docker-compose.prod.yml pull gateway && docker compose -f docker-compose.prod.yml up -d gateway
   ```
3. **Confirmar el driver de Docker** (explica el arreglo de cAdvisor):
   ```bash
   docker info -f '{{.Driver}}'          # "overlayfs" = almacén de containerd (Docker 29)
   ls -l /run/containerd/containerd.sock # debe existir
   ```
4. **Levantar los exporters**:
   ```bash
   cd /opt/mani/exporters
   docker compose -f docker-compose.exporters.yml --env-file /opt/mani/.env.prod up -d
   ```
5. **Cerrar los puertos a todo lo que no sea Calidad.** Docker publica puertos por encima de `ufw`, así que la regla va en la cadena `DOCKER-USER`:
   ```bash
   for p in 9100 8081 9187 4040; do
     sudo iptables -I DOCKER-USER -p tcp -m conntrack --ctorigdstport $p --ctdir ORIGINAL ! -s 10.43.98.196 -j DROP
   done
   sudo netfilter-persistent save   # o el mecanismo que use la VM para persistir iptables
   ```
   Comprobar desde otra máquina de la red que `curl -m 3 http://10.43.98.203:9100/metrics` ya no responde, y desde Calidad que sí.
6. **Verificar desde la VM de PROD**:
   ```bash
   curl -s localhost:9100/metrics | grep -c '^node_cpu_seconds_total'
   curl -s localhost:8081/metrics | grep 'container_cpu_usage_seconds_total{' | grep -o 'name="mani-[^"]*"' | sort -u
   curl -s localhost:4040/metrics | grep 'nginx_http_response_count_total' | grep -o 'route="[^"]*"' | sort -u
   curl -s localhost:9187/metrics | grep -c '^pg_stat_activity_count'
   ```
   La segunda orden debe listar los contenedores `mani-*`. Si solo hay series sin `name`, revisar `docker logs mani-prod-cadvisor`.

## Reversión

```bash
cd /opt/mani/exporters && docker compose -f docker-compose.exporters.yml down
```
No toca la aplicación. El volumen del Gateway (paso 2) puede quedarse.
