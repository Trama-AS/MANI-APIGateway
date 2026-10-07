# CLAUDE.md — Directrices de Desarrollo para MANI-APIGateway

Este archivo resume las instrucciones de contexto, arquitectura de comunicación y buenas prácticas para este repositorio.

---

## 1. Visión General de la Arquitectura
**MANI-APIGateway** es la fachada y router NGINX del ecosistema SOA de MANI. Toda comunicación entre el cliente **`MANI-Flutter`** y los servicios backend se realiza **a través de este componente**.

```
[ MANI-Flutter ] (Cliente Web/Móvil)
        |
        v HTTP /80
[ MANI-APIGateway ] (NGINX)
   ├── /api/v1/core/*     ──> [ MANI-Node ] (:3000)
   ├── /api/v1/rules/*    ──> [ MANI-Rules-Java ] (:8080)
   └── /api/v1/dispatch/* ──> [ MANI-Dispatch-DotNet ] (:5000)
```

---

## 2. Servicios Conectados y Reglas de Enrutamiento

1. **`MANI-Node` (Backend Core):**
   * Upstream: `core-service:3000`
   * Ruta: `/api/v1/core/` (hace `proxy_pass http://core_service/;`).
   * Contenido: Autenticación, perfiles, clientes, aliados, KYC, catálogos.

2. **`MANI-Java` (Rules Service):**
   * Upstream: `rules-service:8080`
   * Ruta: `/api/v1/rules/` (hace `proxy_pass http://rules_service/;`).
   * Contenido: Evaluación de reglas por tenant, rangos tarifarios, validación de condiciones de servicio.

3. **`MANI-.NET` (Dispatch Service):**
   * Upstream: `dispatch-service:5000`
   * Ruta: `/api/v1/dispatch/` (hace `proxy_pass http://dispatch_service/;`).
   * Contenido: Despacho de manicuristas, matching geográfico, exclusión concurrente atómica.

---

## 3. Convenciones Técnicas Obligatorias
* **Inmutabilidad de Encabezados:** No modificar ni consumir el payload del token JWT en el Gateway; delegar la validación de claims al backend correspondiente.
* **Correlation ID:** Asegurar que `X-Correlation-ID` siempre esté presente para trazabilidad distribuida en logs.
* **CORS:** Headers pre-configurados para admitir navegadores web SPA (Flutter Web).
* **Logs Estructurados:** Utilizar el formato JSON definido en `nginx.conf` para ingesta de métricas y observabilidad.

---

## 4. Infraestructura Compartida (CFG-33)
* Este repo es el dueño de `database/` (init, migraciones y verificaciones), `scripts/` y `supabase/`, traídos desde `MANI-Flutter`.
* **Migraciones:** archivo nuevo `database/migrations/NNN_descripcion.sql`, idempotente y con registro en `schema_migrations`. Una migración fusionada **nunca** se edita ni se borra: se corrige con una migración nueva.
* **Sin lógica nueva en PL/pgSQL** (ADR-0022): la lógica de negocio vive en los servicios.
* La BD local se levanta con el perfil `db` (`docker compose --profile db up -d`). Quién aplica las migraciones en cada ambiente está en el `README.md`.
* Mantener LF en `.sh` y `.sql` (`.gitattributes`).
