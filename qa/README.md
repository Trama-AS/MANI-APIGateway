# Regresión del Sprint 4 contra QA (SCRUM-1267)

Suites de regresión funcional, API, E2E y multi-tenant que se ejecutan contra el ambiente de QA
(`10.43.100.141`, rama `release`, imágenes `:staging`) a través del API Gateway real.

| Ruta | Qué es | Subtarea |
|---|---|---|
| `newman/generar_coleccion.js` | Genera `newman/mani_regresion_sprint4.postman_collection.json` (casos por historia, perímetro y cross-tenant B1-B6). No editar el JSON a mano. | SCRUM-1277 / SCRUM-1279 |
| `ejecutar_newman_qa.sh` | Firma tokens HS256 de prueba con el secreto de QA, corre Newman en contenedor y redacta el reporte. | SCRUM-1277 |
| `playwright/` | Landing (SCRUM-1335), configuración de Flutter Web y recorrido E2E 1072 → 861/862 → 1073 → 1074. | SCRUM-1278 |
| `ejecutar_playwright_qa.sh` | Corre la suite Playwright en la imagen oficial `mcr.microsoft.com/playwright:v1.48.2-jammy`. | SCRUM-1278 |
| `../.github/workflows/qa-regresion.yml` | Gate de CI: Newman contra QA desde el runner `nbig02-calidad` (requiere el secreto `QA_JWT_SECRET`). | SCRUM-1277 |

## Ejecución

En la VM de QA (los tokens se firman con `SUPABASE_JWT_SECRET` de `/opt/mani/.env.qa` y no salen de la VM):

```bash
COLECCION=qa/newman/mani_regresion_sprint4.postman_collection.json bash qa/ejecutar_newman_qa.sh
SUITE_DIR=qa/playwright bash qa/ejecutar_playwright_qa.sh
```

Desde la VM de Calidad (alcanza QA por la red privada):

```bash
BASE_URL=http://10.43.100.141 ENV_QA=/ruta/a/archivo_con_SUPABASE_JWT_SECRET COLECCION=qa/newman/mani_regresion_sprint4.postman_collection.json bash qa/ejecutar_newman_qa.sh
```

## Datos

Los casos usan los tenants de prueba de MANI-QA `acme-servicios` (t1) y `nova-mantenimiento` (t2), y el
tenant `poc-concurrencia` para la doble aceptación. Cada corrida crea datos marcados con `QA <corrida>`
(empleado, cliente empresa, sede, categoría, ausencia, consentimiento y solicitud).

## Evidencia

Los reportes se redactan antes de salir de la VM: los tokens se reemplazan por `<token_redactado>`. Los
traces de Playwright contienen tokens ya vencidos (15 min) y se conservan solo en la VM. El reporte de
resultados vive en MANI-docs (`product/REPORTE_QA_REGRESION_SCRUM-1267.md`).
