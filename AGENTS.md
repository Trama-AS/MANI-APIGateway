# AGENTS.md — MANI-APIGateway

Bienvenido al repositorio **MANI-APIGateway**. Este archivo sirve como directriz operativa para agentes de IA y desarrolladores trabajando en la capa de entrada del ecosistema distribuido MANI.

---

## 1. Rol y Propósito del Repositorio
* **Tecnología:** NGINX (Alpine Linux).
* **Responsabilidad:** Único punto de entrada HTTP (puerto 80) para clientes externos (Web y Móvil). Centraliza el enrutamiento hacia microservicios internos, inyección de encabezados de observabilidad (`X-Correlation-ID`), soporte CORS transversal y balanceo de carga.
* **Política:** El Gateway **no contiene lógica de negocio pesada** ni persistencia directa; actúa estrictamente como proxy inverso y distribuidor de tráfico.

---

## 2. Mapa de Comunicación entre Repositorios

| Repositorio Destino | Prefijo de Ruta en Gateway | Puerto Interno | Propósito Operativo |
| :--- | :--- | :--- | :--- |
| **`MANI-Node`** (Core) | `/api/v1/core/*` | `3000` | Gestión de usuarios, tenants, perfiles, KYC, catálogos e historial. |
| **`MANI-Rules-Java`** (Rules) | `/api/v1/rules/*` | `8080` | Motor de reglas de negocio por tenant, cálculo de tarifas y ranking de aliados. |
| **`MANI-Dispatch-DotNet`** (Dispatch) | `/api/v1/dispatch/*` | `5000` | Asignación, despacho, algoritmo de cercanía y exclusión concurrente (409 Conflict). |

* **Cliente Consumidor:** **`MANI-Flutter`** envía todas sus peticiones HTTP al Gateway en `http://<host>:80`.

---

## 3. Protocolos y Estándares de Comunicación
1. **Propagación de Trazabilidad:** NGINX captura o autogenera el encabezado `X-Correlation-ID` en cada solicitud y lo propaga a todos los servicios backend para trazabilidad en logs.
2. **Propagación de Identidad:** El encabezado `Authorization: Bearer <JWT>` se transfiere intacto a los microservicios sin alteración para validación de claims y políticas RLS/Tenant.
3. **Healthcheck:** Ruta `/health` expuesta para balanceadores y monitores de infraestructura.

---

## 4. Comandos de Operación Rápida
```bash
# Validar sintaxis de configuración NGINX
docker run --rm -v ${PWD}/nginx.conf:/etc/nginx/nginx.conf nginx:alpine nginx -t

# Levantar entorno local con Docker Compose
docker-compose up -d --build
```
