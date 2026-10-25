# Regresión del Sprint 4 contra QA (SCRUM-1267)

Suites de regresión funcional, API, E2E y multi-tenant que se ejecutan contra el ambiente de QA
(`10.43.100.141`, rama `release`, imágenes `:staging`) a través del API Gateway real.

| Ruta | Qué es | Subtarea |
|---|---|---|
| `newman/generar_coleccion.js` | Genera `newman/mani_regresion_sprint4.postman_collection.json` (77 casos en 18 carpetas: perímetro, cross-tenant B1-B6 y las historias del Sprint 4; 1074-05 y 1074-06 excluidos). No editar el JSON a mano. | SCRUM-1277 / SCRUM-1279 |
| `ejecutar_newman_qa.sh` | Firma tokens HS256 de prueba con el secreto de QA, corre Newman en contenedor, decodifica y enmascara las respuestas y verifica que el reporte no tenga credenciales. | SCRUM-1277 |
| `playwright/` | Landing (SCRUM-1335), configuración de Flutter Web y recorrido E2E por API 1072 → 861/862 → 1073 → 1074. | SCRUM-1278 |
| `playwright/tests/cors_preflight.spec.js` | Preflight `OPTIONS` con `Origin` de Flutter Web y los encabezados propios que envía la app (incluido `Idempotency-Key`). Newman y los casos con `request` no hacen preflight. | SCRUM-1278 |
| `playwright/tests/smoke_ambiente.spec.js` | Smoke con una cuenta real: health de los 4 servicios, login en el Supabase del `/assets/.env` publicado, claims `tenant_id`/`user_role` del token (hook activo) y petición autenticada a Core y Dispatch. Se omite sin `SMOKE_EMAIL`/`SMOKE_PASSWORD`. | SCRUM-1278 |
| `ejecutar_playwright_qa.sh` | Corre la suite Playwright en la imagen oficial `mcr.microsoft.com/playwright:v1.48.2-jammy` con `npm ci`. | SCRUM-1278 |
| `../.github/workflows/qa-regresion.yml` | Gate de CI: jobs `newman_qa` y `playwright_qa` en el runner `[self-hosted, calidad]` con el environment `qa-regresion`. | SCRUM-1277 / SCRUM-1278 |

## Relación con las colecciones de `postman/`

`postman/MANI-Core.postman_collection.json` y `postman/MANI-Rules.postman_collection.json` se generan desde los
contratos OpenAPI y corren en `ci.yml` contra servicios en memoria: verifican el contrato. La colección de `qa/`
corre contra el ambiente de QA desplegado, con datos de MANI-QA y varios tenants: verifica el comportamiento
integrado (Gateway, Core, Rules y Dispatch). Ninguna reemplaza a la otra.

## Ejecución

En la VM de QA (los tokens se firman con `SUPABASE_JWT_SECRET` de `/opt/mani/.env.qa` y no salen de la VM):

```bash
COLECCION=qa/newman/mani_regresion_sprint4.postman_collection.json bash qa/ejecutar_newman_qa.sh
SUITE_DIR=qa/playwright bash qa/ejecutar_playwright_qa.sh
```

Desde la VM de Calidad (alcanza QA por la red privada):

```bash
BASE_URL=http://10.43.100.141 ENV_QA=/ruta/a/archivo_con_SUPABASE_JWT_SECRET COLECCION=qa/newman/mani_regresion_sprint4.postman_collection.json bash qa/ejecutar_newman_qa.sh
URL_GATEWAY=http://10.43.100.141 URL_FLUTTER=http://10.43.100.141:8080 URL_LANDING=http://10.43.100.141:3001 ENV_QA=/ruta/a/archivo_con_SUPABASE_JWT_SECRET SUITE_DIR=qa/playwright bash qa/ejecutar_playwright_qa.sh
```

### Smoke de producción (después de cada despliegue)

Solo corre los casos sin tokens sintéticos (`SIN_TOKENS=1`), con una cuenta dedicada de smoke de PROD. La contraseña
se pasa por el entorno y no se imprime:

```bash
SIN_TOKENS=1 ARCHIVOS="cors_preflight smoke_ambiente" URL_GATEWAY=<gateway PROD> URL_FLUTTER=<flutter PROD> \
  SMOKE_EMAIL=<cuenta smoke> SMOKE_PASSWORD=<...> SMOKE_TENANT_ID=<uuid tenant demo> \
  SALIR_CON_CODIGO=1 SUITE_DIR=qa/playwright bash qa/ejecutar_playwright_qa.sh
```

Un fallo en `CORS-*` es un encabezado que el navegador bloquea; en `SMK-03`, el hook de claims apagado; en `SMK-04` o
`SMK-05`, Core o Dispatch rechazan el token real. El preflight también corre en `ci.yml` contra la imagen del Gateway
(`tests/gateway/cors-preflight.sh`).

## Gate de CI

Los jobs corren en el runner `nbig02-calidad` (etiqueta `calidad`) de la guía CFG4-03, que alcanza QA por la red
privada; los ejecutores usan Docker en ese runner. Configuración vigente en MANI-APIGateway (habilitada por QA el
20 de octubre de 2026):

1. Environment `qa-regresion` con revisor obligatorio (Santiago Hernández) y el secreto de environment `QA_JWT_SECRET`
   (JWT secret legado de MANI-QA).
2. Variables de repositorio `QA_GATEWAY_URL=http://10.43.100.141`, `QA_FLUTTER_URL=http://10.43.100.141:8080` y
   `QA_LANDING_URL=http://10.43.100.141:3001`.
3. Variable de repositorio `QA_REGRESION_HABILITADA=true`. `QA_REGRESION_HABILITADA` debe ser de repositorio y no de
   environment, porque el `if` del job se evalúa antes de entrar al environment.

Cada PR hacia `develop` o `release` que toque `qa/**` o el workflow dispara los dos jobs, y cada job espera la
aprobación del revisor antes de usar el secreto. Una aserción fallida deja el job en rojo; el gate no es un check
obligatorio de la rama (el obligatorio es Sonar Quality Gate). Para apagarlo, basta con quitar
`QA_REGRESION_HABILITADA`: los jobs vuelven a quedar omitidos. Se publican como artefacto
la evidencia redactada de Newman y el resumen y las capturas de Playwright; el reporte HTML y los traces no se
publican porque contienen tokens de prueba (ya vencidos) y el repositorio es público.

## Datos

Los casos usan los tenants de prueba de MANI-QA `acme-servicios` (t1) y `nova-mantenimiento` (t2) de
`supabase/seed/seed_qa_multitenant.sql`. Excepciones conocidas, que se llevan a la semilla en la Fase B del plan de QA:

- `aliado_t1b` (aliado de t1 sin servicio asignado, caso 853-02) no está en la semilla.
- Los documentos legales de cada tenant se leen en la corrida (856-00 y 856-01) en lugar de fijar sus IDs.
- 1074-05 y 1074-06 están excluidos: usan la solicitud PoC del tenant `poc-concurrencia`, reservada para QAS-07
  (SCRUM-1266). Se reemplazan por una solicitud creada en la corrida y un segundo aliado elegible de t1.

Cada corrida crea datos marcados con `QA <corrida>` (empleado, cliente empresa, sede, categoría, ausencia y
solicitud). Los casos que dependen de un valor guardado por otro caso (por ejemplo `solicitud_t1`) verifican
primero que el valor exista, para que un id vacío no produzca un falso aprobado.

## Identidad de prueba

Toda la colección usa tokens HS256 sintéticos firmados con el JWT secret legado de MANI-QA. Un usuario real recibe
un token ES256 de Supabase Auth, que `validate-token` de Core rechaza (defecto R-10 del reporte, comprobado en
SCRUM-1266). Por eso los resultados prueban la lógica de los servicios a través del Gateway, no el acceso de un
usuario real.

## Evidencia

Los reportes se redactan antes de salir de la VM. Newman exporta las respuestas como arreglos de bytes; el
ejecutor las decodifica y reemplaza tokens y contraseñas temporales por `<token_redactado>`, `<jwt_redactado>` y
`<redactado>`, y aborta sin guardar evidencia si queda alguna credencial. Los traces de Playwright contienen
tokens ya vencidos (15 min) y se conservan solo en la VM. El reporte de
resultados vive en MANI-docs (`product/REPORTE_QA_REGRESION_SCRUM-1267.md`).

## Advertencias de la suite

- No definir `extraHTTPHeaders` en `playwright/playwright.config.js`: un encabezado personalizado en todas las
  peticiones del navegador provoca preflight CORS contra el CDN de Google (CanvasKit y fuentes) y Flutter Web no
  arranca. El `X-Correlation-ID` se envía solo en las llamadas de API (`cabeceras()` de `tests/datos_qa.js`).
- Los casos FW-02 y FW-03 fallan mientras la imagen de Flutter de QA se construya con `.env.example`: es la
  evidencia del defecto R-04 del reporte, no un error de la prueba.
- El caso 853-04 falla mientras el aliado asignado no pueda leer las reglas del sitio (R-02 del reporte).
