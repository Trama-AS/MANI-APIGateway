# 📜 Convención y Guía de Migraciones de Base de Datos — MANI

> [!WARNING]
> ### ⚠️ Migraciones Congeladas — Serie Histórica (ADR-0030 §1 / HU-M01-05)
> De acuerdo con **[ADR-0030 §1](https://github.com/Trama-AS/MANI-docs/blob/main/wiki/02-arquitectura/adr/ADR-0030-propiedad-esquema-y-frontera-de-datos.md)**, las migraciones de este directorio `database/migrations/` (serie `001`–`008`) se encuentran **congeladas como histórico** y no reciben nuevos cambios.
> 
> La **serie viva canónica** de migraciones versionadas (`0001_` en adelante) es propiedad exclusiva de **`MANI-Node`** y reside en:
> 👉 [`MANI-Node/db/migrations/`](https://github.com/Trama-AS/MANI-Node/tree/develop/db/migrations)
> 
> No agregue archivos a esta carpeta. Toda migración o cambio de esquema debe someterse vía PR a `MANI-Node`.

Este directorio contiene las **migraciones versionadas e incrementales** de la base de datos de MANI. Cada archivo representa un cambio de esquema ordenado cronológicamente que se ejecuta de forma secuencial en todos los ambientes (**DEV**, **QA** y **PROD**).

---

## 🏷️ Convención de Nombres

Cada nueva migración debe seguir el formato de 3 dígitos con descripción en minúsculas separada por guiones bajos:

```text
<numero_secuencial>_<descripcion_en_ingles>.sql
```

**Ejemplos:**
* `001_initial_schema.sql` (Esquema base inicial de 17 tablas)
* `002_add_postal_code_to_sitio.sql`
* `003_create_index_solicitud_estado.sql`

---

## 🛡️ Reglas de Oro para Desarrolladores

1. **Idempotencia Obligatoria:**
   Cada script debe poder ejecutarse múltiples veces sin fallar.
   - Para crear tablas: `CREATE TABLE IF NOT EXISTS ...`
   - Para agregar columnas: `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`
   - Para crear índices: `CREATE INDEX IF NOT EXISTS ...`
2. **Registro al Final del Archivo:**
   Al final de cada script `.sql`, debes registrar la versión en la tabla `schema_migrations`:
   ```sql
   INSERT INTO schema_migrations (version, description)
   VALUES ('002', 'Brief description of changes made')
   ON CONFLICT (version) DO NOTHING;
   ```
3. **Inmutabilidad:**
   Una vez que una migración ha sido mezclada a `develop` o `release`, **NUNCA se modifica ni se borra**. Si necesitas corregir algo, se crea una nueva migración (ej. `003_fix_xxx.sql`).

---

## 🛠️ Cómo Aplicar Migraciones en Local (DEV)

### Opción 1: Aplicar migraciones pendientes (sin perder tus datos)
Si estás en una rama donde un compañero agregó una migración (ej. `002_xxx.sql`):

```powershell
# Ejecuta el script que aplica solo las migraciones faltantes en Docker
.\scripts\migrate-local.ps1
```

### Opción 2: Resetear la base de datos completa (Clean Slate con Seeds)
Si quieres reconstruir la base de datos desde cero aplicando todas las migraciones y datos semilla de prueba:

```bash
docker compose --profile db down -v
docker compose --profile db up -d
```

---

## 🔍 Consultar Migraciones Aplicadas

Puedes verificar qué migraciones han sido aplicadas conectándote a la base de datos (vía Adminer en `http://localhost:8088` o `psql`):

```sql
SELECT * FROM schema_migrations ORDER BY applied_at ASC;
```
