# Seeds de QA

Datos de prueba de MANI-QA (proyecto Supabase `hpsxdotaizzclkeufzct`). Se corren a mano en el
SQL Editor del dashboard, que ejecuta como `postgres`. No forman parte de `database/migrations/`
y el CI no los aplica.

## Volver a sembrar QA

El seed de CFG-04 borra **todo** lo que cuelga de sus dos tenants (`acme-servicios` y
`nova-mantenimiento`) antes de insertar: es su forma de ser idempotente. Eso incluye los usuarios
que CFG-12 siembra en esos mismos tenants (`hook.t1@cfg12.mani.test`, `hook.t2@cfg12.mani.test`) y
los `documento_kyc` que CFG-13 usa. Por eso, después de volver a correrlo, hay que volver a correr
los seeds que dependen de él, en este orden:

| Paso | Archivo | Qué deja |
|---|---|---|
| 1 | `supabase/seed/seed_qa_multitenant.sql` | CFG-04: 2 tenants con admin, cliente, aliado verificado, categoría, sitio, vínculo y cobertura |
| 2 | `supabase/poc-cfg12/20_seed_identidad.sql` | CFG-12: usuarios sin claims de tenant para probar el hook, y un `documento_kyc` por tenant |
| 3 | `supabase/poc-cfg13/20_seed_storage.sql` | CFG-13: alinea `documento_kyc.ruta_storage` con ADR-0013 |
| 4 | `qa/storage/cargar_kyc.mjs` (en **MANI-Flutter**) | CFG-13: sube los PDF al bucket `kyc-documentos`, si no están (ver `qa/storage/README.md` de MANI-Flutter) |
| 5 | `supabase/seed/verificar_aislamiento.sql` | Verificación de CFG-04: 2 filas con 4 usuarios (3 de CFG-04 y 1 de CFG-12), 1 aliado verificado y 1 categoría activa |
| 6 | `database/verify/11-normalizacion-dominios.sql` | Verificación de dominios, hook y `kyc_isolation`: 20/20 |
| 7 | `supabase/seed/seed_qa_sprint5.sql` | TEC-16 (SCRUM-1463): barrios, una cuenta de GoTrue por tipo y tenant, 51 aliados elegibles para el broadcast, categorías y tarifario |
| 8 | `supabase/seed/verificar_siembra_sprint5.sql` | Verificación de TEC-16: todos los chequeos en `ok = true` y el aviso final de que la semilla pasa |

Los pasos 5 y 6 van antes del 7 porque sus conteos esperados son los de CFG-04 sola: después de
la semilla del Sprint 5 cada tenant tiene más usuarios, sitios y aliados.

La semilla del Sprint 5 se corre con `psql`, no con el SQL Editor, porque la contraseña de sus 7
cuentas llega como variable y no queda escrita en el archivo:

```bash
psql "$URL_QA" -v clave_qa="$CLAVE_QA" -f supabase/seed/seed_qa_sprint5.sql
psql "$URL_QA" -f supabase/seed/verificar_siembra_sprint5.sql
```

Es idempotente y no borra nada: correrla otra vez no cambia el estado (tampoco la contraseña de
las cuentas que ya existen).

### Antes de volver a correr CFG-04

CFG-04 se niega a correr si en `auth.users` hay cuentas `@qa.mani.test` con ids que no son los
suyos, y las 7 cuentas del Sprint 5 lo son. Su Parte A ya borra lo de dominio de esas cuentas, así
que antes de CFG-04 solo hay que quitarlas de Auth (desde Authentication > Users o con este
bloque) y, al terminar la tabla de arriba, volver a correr los pasos 7 y 8:

```sql
BEGIN;
DELETE FROM auth.identities WHERE user_id IN (SELECT id FROM auth.users
  WHERE id::text LIKE '30000000-0000-4000-8000-00000000510_'
     OR id::text LIKE '30000000-0000-4000-8000-00000000520_');
DELETE FROM auth.users
 WHERE id::text LIKE '30000000-0000-4000-8000-00000000510_'
    OR id::text LIKE '30000000-0000-4000-8000-00000000520_';
COMMIT;
```

El seed de CFG-12 (paso 2) toma "un aliado" de cada tenant sin orden fijo. Si se vuelve a correr
solo, con la semilla del Sprint 5 ya puesta, puede colgar su `documento_kyc` de otro aliado del
Tenant 1. Por eso el orden completo es siempre el de la tabla.

El seed de CFG-09 (`supabase/poc-cfg09/10_seed_concurrencia.sql`) usa su propio tenant
(`poc-concurrencia`), así que CFG-04 no lo toca y no hace falta repetirlo.

## Valores de dominio

Las tablas usan el formato del código, también en los seeds de CFG-12 y en el assert de estado del KYC de la suite Newman de ADR-0015: MAYÚSCULA en español (`ACTIVO`, `ADMIN_TENANT`, `ALIADO`,
`CLIENTE`, `VERIFICADO`, `PERSONA_NATURAL`, `PERSONA_JURIDICA`, `CIUDAD`, `LOCALIDAD`), que es lo
que comparan las migraciones. Los claims de `auth.users.raw_app_meta_data` (`user_role`, `rol`) van
en minúscula: son el contrato del token de ADR-0018, y el hook de CFG-12 emite `lower(rol)`.
Ver SCRUM-1057.
