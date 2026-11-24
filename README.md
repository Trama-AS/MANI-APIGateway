# MANI-APIGateway — API Gateway del Ecosistema MANI

API Gateway central basado en **NGINX** para la plataforma **MANI** (*TRAMA · Ingeniería de Software*).

Este repositorio actúa como el **único punto de entrada perimetral (puerto 80)** para todas las aplicaciones cliente (`MANI-Flutter` en Web y Móvil), enrutando, securizando y balanceando el tráfico hacia los microservicios backend políglotas.

---

## 🏛️ Rol en la Arquitectura SOA (ADR-0019)

Dentro de la arquitectura orientada a servicios (SOA) de MANI, el Gateway cumple las siguientes responsabilidades transversales:

1. **Punto Único de Entrada:** Oculta la topología y puertos internos de la red de microservicios, exponiendo una API unificada bajo el puerto estándar `80`.
2. **Enrutamiento Reverso:** Despacha peticiones HTTP basándose en el prefijo de la URI hacia el microservicio correspondiente.
3. **Observabilidad Distribuida:** Genera o propaga el encabezado `X-Correlation-ID` en cada solicitud para permitir trazabilidad distribuida extremo a extremo en logs.
4. **Soporte de CORS:** Gestiona políticas de Cross-Origin Resource Sharing (`Access-Control-Allow-*`) para clientes web SPA.
5. **Logs Estructurados en JSON:** Registro de métricas de acceso y latencia (`request_time`, `status`, `x_correlation_id`).

```mermaid
flowchart LR
    Client["MANI-Flutter (Cliente Web/Móvil)"] -->|HTTP /:80| GW["MANI-APIGateway (NGINX)"]
    
    GW -->|/api/v1/core/*| Node["MANI-Node (:3000)<br/>Core, Usuarios, KYC, Tenants"]
    GW -->|/api/v1/rules/*| Java["MANI-Java (:8080)<br/>Motor de Reglas y Tarifas"]
    GW -->|/api/v1/dispatch/*| DotNet["MANI-.NET (:5000)<br/>Despacho y Concurrencia"]
```

---

## 🗺️ Matriz de Enrutamiento

| Prefijo de Ruta Externa | Microservicio Destino | Puerto Interno | Dominio / Responsabilidad |
| :--- | :--- | :---: | :--- |
| **`/health`** | Gateway Local | `80` | Healthcheck del propio API Gateway. |
| **`/api/v1/core/*`** | **`MANI-Node`** | `3000` | Gestión de usuarios, perfiles, KYC, catálogos e historial. |
| **`/api/v1/rules/*`** | **`MANI-Java`** | `8080` | Motor de reglas de negocio, cálculo de tarifas y ranking de aliados. |
| **`/api/v1/dispatch/*`** | **`MANI-.NET`** | `5000` | Algoritmo de cercanía geográfica y exclusión concurrente de asignación. |

---

## 🛠️ Stack Tecnológico

* **Servidor Web / Proxy Reverso:** NGINX Alpine Linux.
* **Contenerización:** Docker & Docker Compose.
* **Red:** Bridge `mani-network`.

---

## 🚀 Ejecución Local

### Prerrequisitos
* Docker y Docker Compose instalados.

### 1. Validar la configuración de NGINX
```bash
docker run --rm -v ${PWD}/nginx.conf:/etc/nginx/nginx.conf nginx:alpine nginx -t
```

### 2. Construir la imagen Docker local
```bash
docker build -t mani-api-gateway:local .
```

### 3. Levantar el Gateway de forma aislada
```bash
docker run -d -p 80:80 --name mani-gateway mani-api-gateway:local
```

### 4. Orquestación Completa con Microservicios
Para levantar el Gateway junto con los microservicios en la red compartida:
```bash
docker-compose up -d --build
```

---

### 5. Base de datos local (perfil `db`)
```bash
cp .env.example .env                    # opcional: puertos y credenciales locales
docker compose --profile db up -d       # PostgreSQL 16 (:5432) + Adminer (http://localhost:8088)
./scripts/migrate-local.sh              # aplica las migraciones pendientes (Windows: .\scripts\migrate-local.ps1)
```
El cliente web se suma con el perfil `web`, después de construir `mani-web:local` en `MANI-Flutter`. Guía completa: [`database/README.md`](database/README.md).

---

## 🧪 Pruebas

```bash
# 1. Sintaxis de NGINX (lo mismo que corre el CI)
docker run --rm -v "${PWD}/nginx.conf:/etc/nginx/nginx.conf" -v "${PWD}/ssl:/etc/nginx/ssl" nginx:alpine \
  sh -c "mkdir -p /var/log/nginx-metrics && nginx -t"

# 2. Contratos OpenAPI
npm ci
npm run validate:openapi
npm run lint:openapi

# 3. Reglas del Gateway, con el Gateway y Core levantados (docker compose up -d)
bash tests/gateway/rutas-internas-core.sh http://localhost   # rutas internas de Core no expuestas
bash tests/gateway/ruta-publica-legal.sh http://localhost    # documentos legales sin token
bash tests/gateway/ruta-publica-metrics.sh http://localhost  # /metrics de Core sin token
bash tests/gateway/limite-foto-perfil.sh http://localhost    # límite de 5 MB de la foto de perfil
bash tests/gateway/cors-preflight.sh http://localhost        # preflight CORS de Flutter Web
bash tests/gateway/metricas-dispatch-rules.sh http://localhost  # necesita también Dispatch y Rules

# 4. Contrato Postman/Newman contra un ambiente
npm run postman:run:dev     # o postman:run:qa
npm run postman:run:rules
```

El CI (`ci.yml`) corre 1 a 3, salvo `metricas-dispatch-rules.sh` (el CI solo levanta Core), y los gates de contrato (Newman vía el Gateway real; Rules con Gateway + Core + MANI-Java). `qa-regresion.yml` corre la regresión de QA en los PR a `develop` y `release` que tocan `qa/`. `Sonar Quality Gate` es check requerido para fusionar.

---

## 🚢 Despliegue

La imagen se construye una sola vez y se promueve entre ambientes; no se reconstruye para PROD (SCRUM-1723 / QAS-24). El despliegue en las VM lo hace **DevOps**.

| Rama o acción | Workflow | Imagen en GHCR | Ambiente |
| :--- | :--- | :--- | :--- |
| Push a `develop` | `docker-publish.yml` | `ghcr.io/trama-as/mani-apigateway:develop` | Integración |
| Push a `release` | `docker-publish.yml` | `ghcr.io/trama-as/mani-apigateway:staging` | **QA** (VM `10.43.100.141`) |
| `promote-latest.yml` (manual, *Run workflow*) | `promote-latest.yml` | `ghcr.io/trama-as/mani-apigateway:latest` = **el mismo digest** de `:staging` | **PROD** |
| Etiqueta `vX.Y.Z` en `main` | `docker-publish.yml` | `ghcr.io/trama-as/mani-apigateway:X.Y.Z` | Versión publicada |

- `monitoring/` (Prometheus, Alertmanager) y el `docker-compose.yml` también viven aquí; los aplica DevOps en cada VM.
- **Rollback:** se vuelve a ejecutar `promote-latest.yml` con el digest anterior, que queda en el resumen de cada ejecución.
- **Flujo de ramas** (rama → PR a `develop` → QA → `release` → `main`, nunca PR directo a `main`): [Ramas, flujo y protección](https://github.com/Trama-AS/MANI-docs/blob/main/wiki/03-repositorios/ramas-flujo-y-proteccion.md). **Ambientes:** [Ambientes y promoción](https://github.com/Trama-AS/MANI-docs/blob/main/wiki/04-proceso/ambientes-y-promocion.md).

---

## 🗄️ Infraestructura Compartida (CFG-33)

Este repositorio es el dueño de la infraestructura compartida que antes vivía en `MANI-Flutter`. El repositorio `MANI-Infra` previsto en ADR-0004 no existe, y el equipo eligió este repo como destino.

| Ruta | Contenido |
| :--- | :--- |
| `database/init/` | Scripts que el contenedor `postgres` ejecuta al crearse (esquema, seeds y funciones) |
| `database/migrations/` | Migraciones versionadas `NNN_descripcion.sql`, idempotentes e inmutables una vez fusionadas ([convención](database/migrations/README.md)) |
| `database/verify/` | Verificaciones SQL (aislamiento multi-tenant, categorías del aliado, dominios) |
| `scripts/` | `migrate-local` y `sync-db-from-qa` (`.sh` y `.ps1`) para la base local |
| `supabase/` | PoC de CFG-09/10/12/13 y seeds de QA ([guía](supabase/seed/README.md)) |

El `nginx.conf` de `MANI-Flutter` **no** se movió: sirve la SPA dentro de la imagen web del cliente y no es configuración del Gateway.

### Quién ejecuta las migraciones en cada ambiente

| Ambiente | Responsable | Cómo |
| :--- | :--- | :--- |
| DEV local | Cada desarrollador | `scripts/migrate-local.*` contra `mani-postgres` |
| DEV / TEST-QA (Supabase) | DevOps | Aplica `database/migrations/` en orden, después de fusionar el PR. Automatizarlo en el pipeline de este repo queda en CFG-29 |
| PROD | DevOps, con aprobación del PR de release | Solo migraciones ya validadas en QA (schema-first, `INFRAESTRUCTURA_MANI.md` §15). Nunca cambios manuales al esquema |

> Pendiente de registrar en `MANI-docs` (`INFRAESTRUCTURA_MANI.md` §15 y enmienda de ADR-0004) dentro de la misma tarea CFG-33.

---

## 🔍 Verificación de Salud (Healthcheck)

```bash
curl -i http://localhost/health
```

**Respuesta esperada:**
```json
{
  "status": "UP",
  "gateway": "MANI-APIGateway",
  "timestamp": "2026-10-05T19:50:00Z"
}
```

---

## 📄 Protocolos y Encabezados Clave

* **`Authorization`:** Se propaga intacto el token `Bearer <JWT>` hacia los microservicios backend para validación de claims y tenant.
* **`X-Correlation-ID`:** Identificador único UUID por petición; si el cliente no lo envía, NGINX lo genera automáticamente.

---

## 📐 Contratos publicados

| Contrato | Servicio | Suite Newman |
| :--- | :--- | :--- |
| `docs/openapi/core.yaml` | MANI-Node (identidad y registro) | `postman/MANI-Core.postman_collection.json` |
| `docs/openapi/core-internal.yaml` | MANI-Node, rutas internas que solo consume Dispatch (`x-internal`; el Gateway las bloquea) | — |
| `docs/openapi/dispatch.yaml` | MANI-.NET (elegibles, broadcast, aceptación y rechazo de ofertas, bandeja del aliado; M-05) | — |
| `docs/openapi/rules.yaml` | MANI-Java (reglas de categoría, US-03.1.1-M6) | `postman/MANI-Rules.postman_collection.json` |

```bash
npm run validate:openapi        # valida los contratos
npm run lint:openapi            # Spectral sobre todos
npm run test:coverage           # pruebas unitarias de los scripts (el Quality Gate exige 80 % en código nuevo)
npm run verificar:contrato -- --contrato core --url http://localhost:3000   # servicio local contra su contrato (SCRUM-1724)
npm run postman:generate:rules  # regenera la colección Rules (no editarla a mano)

# Suite Rules contra el Gateway real (requiere core-service con validate-token y rules-service):
docker compose --profile full up -d
npm run postman:run:rules -- --env-var baseUrl=http://localhost --env-var jwtSecret=<SUPABASE_JWT_SECRET>
```

La suite Rules cubre categoría válida, inválida (nombre, límites 3/60, flujo), inactiva, actualización parcial, autorización por rol, aislamiento de tenant (el `X-Tenant-Id` del cliente se ignora y un `tenantId` ajeno en el cuerpo da `403 TENANT_MISMATCH`) y errores de petición. CI la ejecuta en el job `contract-gate-rules`.

---

## 👥 Equipo y Gobernanza
* **Organización:** [TRAMA · Ingeniería de Software](https://github.com/Trama-AS)
* **Repositorio Oficial:** [MANI-APIGateway](https://github.com/Trama-AS/MANI-APIGateway)
