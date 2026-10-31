-- =====================================================================
-- MANI — Semilla complementaria de QA para el Sprint 5
-- =====================================================================
-- Ticket: SCRUM-1463 (TEC-16)
-- Ambiente: SOLO QA (proyecto Supabase hpsxdotaizzclkeufzct)
-- Corre DESPUÉS de seed_qa_multitenant.sql (CFG-04) y de los seeds que
-- dependen de ella. El orden completo está en supabase/seed/README.md.
--
-- Esquema: migraciones 001-008 de este repositorio más las del Core
-- (MANI-Node/db/migrations). De las del Core usa cliente.razon_social,
-- cliente.nit, cliente.nombre_representante y sitio.nombre (0002),
-- aliado.tipo_documento_identidad y aliado.numero_documento_identidad
-- (0001) y el representante legal del aliado (0008). La Parte 0 falla con
-- un mensaje claro si falta alguna.
--
-- QUÉ AGREGA (sin borrar ni cambiar nada de CFG-04)
--   * 6 barrios (nivel BARRIO): 3 bajo Chapinero y 3 bajo Suba.
--   * 7 cuentas reales de GoTrue para los tipos de cuenta que CFG-04 no trae:
--       Tenant 1: cliente empresa, aliado empresa, empleado directo.
--       Tenant 2: cliente empresa, cliente persona natural, aliado persona
--                 natural, empleado directo.
--     Con eso cada tenant queda con una cuenta por tipo: admin, cliente
--     persona natural, cliente empresa, aliado persona natural, aliado
--     empresa y empleado directo. El aliado empresa del Tenant 2 es el de
--     CFG-04, y su cliente PERSONA_JURIDICA no tiene razón social ni NIT, por
--     eso el Tenant 2 recibe su propio cliente empresa.
--   * 50 aliados de solo dominio en el Tenant 1 (sin auth.users). Con el
--     aliado de CFG-04 suman 51 elegibles en Plomería y Chapinero: el caso de
--     broadcast. Las cuentas nuevas del Tenant 1 no entran en ese conteo
--     (cubren Suba o atienden otra categoría).
--   * Una categoría ACTIVO y una INACTIVO más por tenant.
--   * Una tarifa de referencia por cada categoría activa de cada tenant.
--
-- CÓMO SE CORRE
--   Con psql, no con el SQL Editor del dashboard: el editor no entiende
--   variables de psql. La contraseña de las 7 cuentas llega en `clave_qa`
--   (mínimo 8 caracteres) y nunca queda escrita en este archivo:
--     psql "$URL_QA" -v clave_qa="$CLAVE_QA" -f supabase/seed/seed_qa_sprint5.sql
--   Usar una contraseña desechable de QA, nunca una real.
--
-- IDEMPOTENCIA
--   Una sola transacción, UUIDs fijos y ON CONFLICT DO NOTHING en todo. No
--   hay DELETE ni UPDATE de filas existentes, salvo rellenar con '' las
--   columnas de token de GoTrue que estén en NULL en las 7 cuentas nuevas.
--   Una segunda corrida no cambia nada, tampoco la contraseña de una cuenta
--   que ya existe. Verificar con supabase/seed/verificar_siembra_sprint5.sql.
--
-- ⚠️ SI SE VUELVE A CORRER CFG-04
--   CFG-04 borra todo lo que cuelga de sus dos tenants, también lo de este
--   archivo, y se niega a correr si hay cuentas @qa.mani.test con otros ids,
--   como las 7 de aquí. El README trae el paso para quitarlas antes. Después
--   de CFG-04 se vuelve a correr esta semilla.
--
-- UUIDs FIJOS — convención de CFG-04: <E>0000000-0000-4000-8000-<grupo>
--   E: igual que CFG-04 (1 tenant · 2 zona · 3 usuario · 4 cliente
--      5 aliado · 6 categoria · 7 sitio · 8 aliado_categoria · 9 cobertura)
--      y `a` = tarifa_referencia.
--   El último grupo es 00000000<B><T><II>: B = bloque, T = tenant (1/2,
--   0 = global), II = índice. CFG-04 ocupa el bloque 0.
--     Bloque 5: cuentas, catálogo, sitios y tarifas de este archivo.
--     Bloque 6: los 50 aliados de broadcast del Tenant 1 (II = 01..50).
--   El cliente o aliado de una cuenta usa el mismo índice que su usuario.
--
--   ZONAS (BARRIO, globales)
--     20000000-0000-4000-8000-000000005001..5003  Chapinero Alto, Quinta Camacho, Chico Norte
--     20000000-0000-4000-8000-000000005004..5006  Niza, Suba Centro, La Campina
--   CUENTAS (usuario.id = auth.users.id)
--     30000000-0000-4000-8000-000000005101  cliente_empresa.t1@qa.mani.test   CLIENTE  PERSONA_JURIDICA
--     30000000-0000-4000-8000-000000005102  aliado_empresa.t1@qa.mani.test    ALIADO   PERSONA_JURIDICA
--     30000000-0000-4000-8000-000000005103  empleado_directo.t1@qa.mani.test  ALIADO   EMPLEADO_DIRECTO
--     30000000-0000-4000-8000-000000005201  cliente_empresa.t2@qa.mani.test   CLIENTE  PERSONA_JURIDICA
--     30000000-0000-4000-8000-000000005202  cliente_natural.t2@qa.mani.test   CLIENTE  PERSONA_NATURAL
--     30000000-0000-4000-8000-000000005203  aliado_natural.t2@qa.mani.test    ALIADO   PERSONA_NATURAL
--     30000000-0000-4000-8000-000000005204  empleado_directo.t2@qa.mani.test  ALIADO   EMPLEADO_DIRECTO
--   ALIADOS DE BROADCAST (Tenant 1, sin cuenta de Auth)
--     30000000-…-0000000061II / 50000000-…-0000000061II, II = 01..50
--     correo aliado_broadcast_II.t1@qa.mani.test, documento 10000061II
--   CATEGORÍAS
--     60000000-0000-4000-8000-000000005101  Cerrajeria   T1  ACTIVO
--     60000000-0000-4000-8000-000000005102  Jardineria   T1  INACTIVO
--     60000000-0000-4000-8000-000000005201  Pintura      T2  ACTIVO
--     60000000-0000-4000-8000-000000005202  Carpinteria  T2  INACTIVO
-- =====================================================================

\set ON_ERROR_STOP on

-- La contraseña se valida antes de abrir la transacción: sin ella psql
-- dejaría el texto `:'clave_qa'` tal cual y el error sería confuso.
\if :{?clave_qa}
  SELECT length(:'clave_qa') >= 8 AS clave_qa_valida \gset
  \if :clave_qa_valida
  \else
    DO $$ BEGIN RAISE EXCEPTION 'clave_qa debe tener al menos 8 caracteres.'; END $$;
  \endif
\else
  DO $$ BEGIN RAISE EXCEPTION 'Falta la contraseña de las cuentas: psql -v clave_qa=... -f supabase/seed/seed_qa_sprint5.sql'; END $$;
\endif

BEGIN;

-- Igual que CFG-04: pgcrypto vive en `extensions` en Supabase.
SET LOCAL search_path = public, extensions;

-- Cuentas de GoTrue de este archivo. Se usan en auth.users, auth.identities
-- y usuario; la tabla temporal desaparece con el COMMIT.
CREATE TEMP TABLE cuenta_sprint5 (
  id        uuid PRIMARY KEY,
  tenant_id uuid NOT NULL,
  email     text NOT NULL,
  rol       text NOT NULL,   -- minúscula: contrato del token (ADR-0018)
  nombre    text NOT NULL
) ON COMMIT DROP;

INSERT INTO cuenta_sprint5 (id, tenant_id, email, rol, nombre) VALUES
  ('30000000-0000-4000-8000-000000005101', '10000000-0000-4000-8000-000000000011', 'cliente_empresa.t1@qa.mani.test',  'cliente', 'Cliente Empresa QA Tenant 1'),
  ('30000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', 'aliado_empresa.t1@qa.mani.test',   'aliado',  'Aliado Empresa QA Tenant 1'),
  ('30000000-0000-4000-8000-000000005103', '10000000-0000-4000-8000-000000000011', 'empleado_directo.t1@qa.mani.test', 'aliado',  'Empleado Directo QA Tenant 1'),
  ('30000000-0000-4000-8000-000000005201', '10000000-0000-4000-8000-000000000021', 'cliente_empresa.t2@qa.mani.test',  'cliente', 'Cliente Empresa QA Tenant 2'),
  ('30000000-0000-4000-8000-000000005202', '10000000-0000-4000-8000-000000000021', 'cliente_natural.t2@qa.mani.test',  'cliente', 'Cliente Natural QA Tenant 2'),
  ('30000000-0000-4000-8000-000000005203', '10000000-0000-4000-8000-000000000021', 'aliado_natural.t2@qa.mani.test',   'aliado',  'Aliado Natural QA Tenant 2'),
  ('30000000-0000-4000-8000-000000005204', '10000000-0000-4000-8000-000000000021', 'empleado_directo.t2@qa.mani.test', 'aliado',  'Empleado Directo QA Tenant 2');

-- ---------------------------------------------------------------------
-- PARTE 0 — Guardas
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_faltantes text;
BEGIN
  -- CFG-04 primero: esta semilla cuelga de sus tenants, zonas y categorías.
  SELECT string_agg(x.id::text, ', ')
    INTO v_faltantes
    FROM (VALUES
      ('10000000-0000-4000-8000-000000000011'::uuid, 'tenant'),
      ('10000000-0000-4000-8000-000000000021'::uuid, 'tenant'),
      ('20000000-0000-4000-8000-000000000002'::uuid, 'zona'),
      ('20000000-0000-4000-8000-000000000003'::uuid, 'zona'),
      ('30000000-0000-4000-8000-000000000011'::uuid, 'usuario'),
      ('30000000-0000-4000-8000-000000000021'::uuid, 'usuario'),
      ('50000000-0000-4000-8000-000000000011'::uuid, 'aliado'),
      ('60000000-0000-4000-8000-000000000011'::uuid, 'categoria_servicio'),
      ('60000000-0000-4000-8000-000000000021'::uuid, 'categoria_servicio')
    ) AS x(id, tabla)
   WHERE CASE x.tabla
           WHEN 'tenant'             THEN NOT EXISTS (SELECT 1 FROM tenant             WHERE id = x.id)
           WHEN 'zona'               THEN NOT EXISTS (SELECT 1 FROM zona               WHERE id = x.id)
           WHEN 'usuario'            THEN NOT EXISTS (SELECT 1 FROM usuario            WHERE id = x.id)
           WHEN 'aliado'             THEN NOT EXISTS (SELECT 1 FROM aliado             WHERE id = x.id)
           WHEN 'categoria_servicio' THEN NOT EXISTS (SELECT 1 FROM categoria_servicio WHERE id = x.id)
         END;

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Faltan filas de CFG-04 (%). Corre supabase/seed/seed_qa_multitenant.sql antes que esta semilla.',
      v_faltantes;
  END IF;

  -- Columnas de las migraciones del Core que usa este archivo.
  SELECT string_agg(c.tabla || '.' || c.columna, ', ')
    INTO v_faltantes
    FROM (VALUES
      ('cliente', 'razon_social'), ('cliente', 'nit'), ('cliente', 'nombre_representante'),
      ('sitio', 'nombre'),
      ('aliado', 'tipo_documento_identidad'), ('aliado', 'numero_documento_identidad'),
      ('aliado', 'nombre_representante_legal'), ('aliado', 'documento_representante_legal'),
      ('aliado', 'verificado_por'), ('aliado', 'fecha_verificacion'),
      ('categoria_servicio', 'flujo_operativo'), ('categoria_servicio', 'creado_por')
    ) AS c(tabla, columna)
   WHERE NOT EXISTS (
     SELECT 1 FROM information_schema.columns ic
      WHERE ic.table_schema = 'public' AND ic.table_name = c.tabla AND ic.column_name = c.columna
   );

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Faltan columnas en el esquema: %. Aplica las migraciones 002-008 de este repo y las de MANI-Node/db/migrations.',
      v_faltantes;
  END IF;

  -- ON CONFLICT DO NOTHING también se traga un choque contra un UNIQUE que
  -- no es el id. Si alguien creó a mano una fila con el mismo correo, NIT,
  -- documento o nombre de categoría pero otro id, la fila de aquí no entra
  -- y lo que cuelga de ella falla después por FK. Mejor fallar aquí.
  SELECT string_agg(u.email, ', ')
    INTO v_faltantes
    FROM auth.users u
    JOIN cuenta_sprint5 c ON lower(c.email) = lower(u.email)
   WHERE u.id <> c.id;

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existe(n) usuario(s) de Auth con email % pero con otro id. Bórralos desde Authentication > Users antes de sembrar.',
      v_faltantes;
  END IF;

  SELECT string_agg(cs.nombre, ', ')
    INTO v_faltantes
    FROM categoria_servicio cs
    JOIN (VALUES
      ('60000000-0000-4000-8000-000000005101'::uuid, '10000000-0000-4000-8000-000000000011'::uuid, 'cerrajeria'),
      ('60000000-0000-4000-8000-000000005102'::uuid, '10000000-0000-4000-8000-000000000011'::uuid, 'jardineria'),
      ('60000000-0000-4000-8000-000000005201'::uuid, '10000000-0000-4000-8000-000000000021'::uuid, 'pintura'),
      ('60000000-0000-4000-8000-000000005202'::uuid, '10000000-0000-4000-8000-000000000021'::uuid, 'carpinteria')
    ) AS n(id, tenant_id, nombre)
      ON n.tenant_id = cs.tenant_id AND n.nombre = lower(btrim(cs.nombre))
   WHERE cs.id <> n.id;

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existe(n) categoría(s) % con otro id en los tenants seed. Renómbralas o bórralas antes de sembrar.',
      v_faltantes;
  END IF;

  SELECT string_agg(a.numero_documento_identidad, ', ')
    INTO v_faltantes
    FROM aliado a
   WHERE a.tenant_id IN ('10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000021')
     AND (a.numero_documento_identidad IN ('900005102', '1000005103', '1000005203', '1000005204')
          OR a.numero_documento_identidad LIKE '10000061__')
     AND a.id::text NOT LIKE '50000000-0000-4000-8000-00000000510_'
     AND a.id::text NOT LIKE '50000000-0000-4000-8000-00000000520_'
     AND a.id::text NOT LIKE '50000000-0000-4000-8000-0000000061__';

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existe(n) aliado(s) con documento % y otro id en los tenants seed.', v_faltantes;
  END IF;

  SELECT string_agg(c.nit, ', ')
    INTO v_faltantes
    FROM cliente c
   WHERE c.tenant_id IN ('10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000021')
     AND c.nit IN ('900005101', '900005201')
     AND c.id NOT IN ('40000000-0000-4000-8000-000000005101', '40000000-0000-4000-8000-000000005201');

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION
      'Ya existe(n) cliente(s) con NIT % y otro id en los tenants seed.', v_faltantes;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- PARTE 1 — Barrios (globales, como las zonas de CFG-04)
-- ---------------------------------------------------------------------
INSERT INTO zona (id, nivel, nombre, zona_padre_id, estado) VALUES
  ('20000000-0000-4000-8000-000000005001', 'BARRIO', 'Chapinero Alto', '20000000-0000-4000-8000-000000000002', 'ACTIVO'),
  ('20000000-0000-4000-8000-000000005002', 'BARRIO', 'Quinta Camacho', '20000000-0000-4000-8000-000000000002', 'ACTIVO'),
  ('20000000-0000-4000-8000-000000005003', 'BARRIO', 'Chico Norte',    '20000000-0000-4000-8000-000000000002', 'ACTIVO'),
  ('20000000-0000-4000-8000-000000005004', 'BARRIO', 'Niza',           '20000000-0000-4000-8000-000000000003', 'ACTIVO'),
  ('20000000-0000-4000-8000-000000005005', 'BARRIO', 'Suba Centro',    '20000000-0000-4000-8000-000000000003', 'ACTIVO'),
  ('20000000-0000-4000-8000-000000005006', 'BARRIO', 'La Campina',     '20000000-0000-4000-8000-000000000003', 'ACTIVO')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- PARTE 2 — Cuentas de Supabase Auth (mismo patrón que CFG-04, B.1)
-- ---------------------------------------------------------------------
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
)
SELECT c.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       c.email, crypt(:'clave_qa', gen_salt('bf')), now(),
       jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'),
                          'tenant_id', c.tenant_id::text, 'user_role', c.rol, 'rol', c.rol),
       jsonb_build_object('nombre', c.nombre), now(), now(), false, false
  FROM cuenta_sprint5 c
ON CONFLICT DO NOTHING;

-- Columnas de token en '' y no en NULL: GoTrue las lee como string de Go y
-- con NULL el login falla (ver CFG-04).
UPDATE auth.users u
   SET confirmation_token         = COALESCE(u.confirmation_token, ''),
       recovery_token             = COALESCE(u.recovery_token, ''),
       email_change               = COALESCE(u.email_change, ''),
       email_change_token_new     = COALESCE(u.email_change_token_new, ''),
       email_change_token_current = COALESCE(u.email_change_token_current, ''),
       reauthentication_token     = COALESCE(u.reauthentication_token, ''),
       phone_change               = COALESCE(u.phone_change, ''),
       phone_change_token         = COALESCE(u.phone_change_token, '')
  FROM cuenta_sprint5 c
 WHERE u.id = c.id
   AND (u.confirmation_token IS NULL OR u.recovery_token IS NULL OR u.email_change IS NULL
        OR u.email_change_token_new IS NULL OR u.email_change_token_current IS NULL
        OR u.reauthentication_token IS NULL OR u.phone_change IS NULL OR u.phone_change_token IS NULL);

-- auth.identities según la versión de GoTrue, como en CFG-04. El NOT EXISTS
-- hace la segunda corrida inofensiva en ambas formas de la tabla.
DO $$
DECLARE
  v_tiene_provider_id boolean;
  v_id_es_uuid        boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'auth' AND table_name = 'identities'
       AND column_name = 'provider_id'
  ) INTO v_tiene_provider_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'auth' AND table_name = 'identities'
       AND column_name = 'id' AND data_type = 'uuid'
  ) INTO v_id_es_uuid;

  IF v_tiene_provider_id AND v_id_es_uuid THEN
    -- GoTrue actual: id uuid propio + provider_id NOT NULL
    INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT gen_random_uuid(), u.id, u.id::text, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u
      JOIN cuenta_sprint5 c ON c.id = u.id
     WHERE NOT EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = u.id AND i.provider = 'email')
    ON CONFLICT DO NOTHING;

  ELSIF NOT v_tiene_provider_id THEN
    -- GoTrue legacy: id text = el sub del proveedor, sin provider_id
    INSERT INTO auth.identities (id, user_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    SELECT u.id::text, u.id, 'email',
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
           now(), now(), now()
      FROM auth.users u
      JOIN cuenta_sprint5 c ON c.id = u.id
     WHERE NOT EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = u.id AND i.provider = 'email')
    ON CONFLICT DO NOTHING;

  ELSE
    RAISE EXCEPTION
      'Forma inesperada de auth.identities (provider_id=%, id uuid=%). Revisar columnas y ajustar este bloque.',
      v_tiene_provider_id, v_id_es_uuid;
  END IF;
END $$;

-- usuario: id = auth.users.id y rol en mayúscula. custom_access_token_hook
-- (migración 007) toma de aquí el tenant y el rol del token.
INSERT INTO usuario (id, tenant_id, email, rol, estado)
SELECT c.id, c.tenant_id, c.email, upper(c.rol), 'ACTIVO'
  FROM cuenta_sprint5 c
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- PARTE 3 — Catálogo: categorías y tarifas
-- ---------------------------------------------------------------------
INSERT INTO categoria_servicio (id, tenant_id, nombre, estado, flujo_operativo, creado_por) VALUES
  ('60000000-0000-4000-8000-000000005101', '10000000-0000-4000-8000-000000000011', 'Cerrajeria',  'ACTIVO',   'COTIZACION_PREVIA', '30000000-0000-4000-8000-000000000011'),
  ('60000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', 'Jardineria',  'INACTIVO', NULL,                '30000000-0000-4000-8000-000000000011'),
  ('60000000-0000-4000-8000-000000005201', '10000000-0000-4000-8000-000000000021', 'Pintura',     'ACTIVO',   'TARIFA_ESTANDAR',   '30000000-0000-4000-8000-000000000021'),
  ('60000000-0000-4000-8000-000000005202', '10000000-0000-4000-8000-000000000021', 'Carpinteria', 'INACTIVO', NULL,                '30000000-0000-4000-8000-000000000021')
ON CONFLICT DO NOTHING;

-- Una tarifa por categoría activa y tenant, incluidas las de CFG-04.
-- Pesos colombianos; valor_min <= valor_tipico <= valor_max.
INSERT INTO tarifa_referencia (id, tenant_id, categoria_id, valor_min, valor_tipico, valor_max) VALUES
  ('a0000000-0000-4000-8000-000000005101', '10000000-0000-4000-8000-000000000011', '60000000-0000-4000-8000-000000000011',  80000, 150000, 350000),  -- Plomeria
  ('a0000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', '60000000-0000-4000-8000-000000005101',  60000, 120000, 250000),  -- Cerrajeria
  ('a0000000-0000-4000-8000-000000005201', '10000000-0000-4000-8000-000000000021', '60000000-0000-4000-8000-000000000021',  90000, 160000, 400000),  -- Electricidad
  ('a0000000-0000-4000-8000-000000005202', '10000000-0000-4000-8000-000000000021', '60000000-0000-4000-8000-000000005201', 200000, 450000, 900000)   -- Pintura
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- PARTE 4 — Clientes y sitios de las cuentas nuevas
-- ---------------------------------------------------------------------
INSERT INTO cliente (id, tenant_id, usuario_id, tipo, razon_social, nit, nombre_representante) VALUES
  ('40000000-0000-4000-8000-000000005101', '10000000-0000-4000-8000-000000000011', '30000000-0000-4000-8000-000000005101', 'PERSONA_JURIDICA', 'Constructora Andina QA SAS', '900005101', 'Laura Gomez QA'),
  ('40000000-0000-4000-8000-000000005201', '10000000-0000-4000-8000-000000000021', '30000000-0000-4000-8000-000000005201', 'PERSONA_JURIDICA', 'Inmobiliaria Sabana QA SAS', '900005201', 'Andres Rojas QA'),
  ('40000000-0000-4000-8000-000000005202', '10000000-0000-4000-8000-000000000021', '30000000-0000-4000-8000-000000005202', 'PERSONA_NATURAL',  NULL,                         NULL,        NULL)
ON CONFLICT DO NOTHING;

-- Cada cliente empresa con 2 sitios, uno en un barrio de Chapinero y otro en
-- uno de Suba.
INSERT INTO sitio (id, tenant_id, cliente_id, zona_id, nombre, direccion, reglas) VALUES
  ('70000000-0000-4000-8000-000000005101', '10000000-0000-4000-8000-000000000011', '40000000-0000-4000-8000-000000005101', '20000000-0000-4000-8000-000000005001', 'Sede principal',  'Carrera 5 #57-20, Chapinero Alto', '{"horario_acceso":"07:00-19:00"}'::jsonb),
  ('70000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', '40000000-0000-4000-8000-000000005101', '20000000-0000-4000-8000-000000005004', 'Bodega Niza',     'Calle 127 #70-15, Niza',           '{"horario_acceso":"08:00-17:00"}'::jsonb),
  ('70000000-0000-4000-8000-000000005201', '10000000-0000-4000-8000-000000000021', '40000000-0000-4000-8000-000000005201', '20000000-0000-4000-8000-000000005002', 'Oficina central', 'Calle 70 #9-45, Quinta Camacho',   '{"horario_acceso":"08:00-18:00"}'::jsonb),
  ('70000000-0000-4000-8000-000000005202', '10000000-0000-4000-8000-000000000021', '40000000-0000-4000-8000-000000005201', '20000000-0000-4000-8000-000000005005', 'Sede Suba',       'Calle 145 #91-19, Suba Centro',    '{"horario_acceso":"09:00-17:00"}'::jsonb),
  ('70000000-0000-4000-8000-000000005203', '10000000-0000-4000-8000-000000000021', '40000000-0000-4000-8000-000000005202', '20000000-0000-4000-8000-000000005003', 'Casa',            'Calle 93 #11-30, Chico Norte',     '{}'::jsonb)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- PARTE 5 — Aliados de las cuentas nuevas
-- ---------------------------------------------------------------------
-- Todos VERIFICADO por el admin de su tenant. Ninguno del Tenant 1 cubre
-- Chapinero en Plomería, para que el conteo de broadcast quede en 51.
INSERT INTO aliado (id, tenant_id, usuario_id, tipo, nombre_razon_social, estado_verificacion,
                    tipo_documento_identidad, numero_documento_identidad,
                    nombre_representante_legal, documento_representante_legal,
                    verificado_por, fecha_verificacion) VALUES
  ('50000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', '30000000-0000-4000-8000-000000005102', 'PERSONA_JURIDICA', 'Cerrajeria Express QA SAS',    'VERIFICADO', 'NIT', '900005102',  'Marta Diaz QA', '52005102', '30000000-0000-4000-8000-000000000011', now()),
  ('50000000-0000-4000-8000-000000005103', '10000000-0000-4000-8000-000000000011', '30000000-0000-4000-8000-000000005103', 'EMPLEADO_DIRECTO', 'Empleado Directo QA Tenant 1', 'VERIFICADO', 'CC',  '1000005103', NULL,            NULL,       '30000000-0000-4000-8000-000000000011', now()),
  ('50000000-0000-4000-8000-000000005203', '10000000-0000-4000-8000-000000000021', '30000000-0000-4000-8000-000000005203', 'PERSONA_NATURAL',  'Aliado Natural QA Tenant 2',   'VERIFICADO', 'CC',  '1000005203', NULL,            NULL,       '30000000-0000-4000-8000-000000000021', now()),
  ('50000000-0000-4000-8000-000000005204', '10000000-0000-4000-8000-000000000021', '30000000-0000-4000-8000-000000005204', 'EMPLEADO_DIRECTO', 'Empleado Directo QA Tenant 2', 'VERIFICADO', 'CC',  '1000005204', NULL,            NULL,       '30000000-0000-4000-8000-000000000021', now())
ON CONFLICT DO NOTHING;

INSERT INTO aliado_categoria (id, tenant_id, aliado_id, categoria_id) VALUES
  ('80000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', '50000000-0000-4000-8000-000000005102', '60000000-0000-4000-8000-000000005101'),  -- Cerrajeria
  ('80000000-0000-4000-8000-000000005103', '10000000-0000-4000-8000-000000000011', '50000000-0000-4000-8000-000000005103', '60000000-0000-4000-8000-000000000011'),  -- Plomeria
  ('80000000-0000-4000-8000-000000005203', '10000000-0000-4000-8000-000000000021', '50000000-0000-4000-8000-000000005203', '60000000-0000-4000-8000-000000000021'),  -- Electricidad
  ('80000000-0000-4000-8000-000000005204', '10000000-0000-4000-8000-000000000021', '50000000-0000-4000-8000-000000005204', '60000000-0000-4000-8000-000000005201')   -- Pintura
ON CONFLICT DO NOTHING;

INSERT INTO cobertura_aliado (id, tenant_id, aliado_id, zona_id) VALUES
  ('90000000-0000-4000-8000-000000005102', '10000000-0000-4000-8000-000000000011', '50000000-0000-4000-8000-000000005102', '20000000-0000-4000-8000-000000000003'),  -- Suba
  ('90000000-0000-4000-8000-000000005103', '10000000-0000-4000-8000-000000000011', '50000000-0000-4000-8000-000000005103', '20000000-0000-4000-8000-000000000003'),  -- Suba
  ('90000000-0000-4000-8000-000000005203', '10000000-0000-4000-8000-000000000021', '50000000-0000-4000-8000-000000005203', '20000000-0000-4000-8000-000000000002'),  -- Chapinero
  ('90000000-0000-4000-8000-000000005204', '10000000-0000-4000-8000-000000000021', '50000000-0000-4000-8000-000000005204', '20000000-0000-4000-8000-000000000003')   -- Suba
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- PARTE 6 — 50 aliados de broadcast en el Tenant 1 (solo dominio)
-- ---------------------------------------------------------------------
-- Cumplen la condición de PgElegibilidadRepository (MANI-Node): usuario
-- ACTIVO del tenant, aliado VERIFICADO, categoría activa y cobertura en una
-- zona activa. No tienen auth.users: nadie inicia sesión con ellos, solo
-- reciben la oferta.
INSERT INTO usuario (id, tenant_id, email, rol, estado)
SELECT ('30000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       '10000000-0000-4000-8000-000000000011',
       'aliado_broadcast_' || lpad(n::text, 2, '0') || '.t1@qa.mani.test',
       'ALIADO', 'ACTIVO'
  FROM generate_series(1, 50) AS n
ON CONFLICT DO NOTHING;

INSERT INTO aliado (id, tenant_id, usuario_id, tipo, nombre_razon_social, estado_verificacion,
                    tipo_documento_identidad, numero_documento_identidad,
                    verificado_por, fecha_verificacion)
SELECT ('50000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       '10000000-0000-4000-8000-000000000011',
       ('30000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       'PERSONA_NATURAL',
       'Aliado Broadcast QA ' || lpad(n::text, 2, '0'),
       'VERIFICADO', 'CC', '10000061' || lpad(n::text, 2, '0'),
       '30000000-0000-4000-8000-000000000011', now()
  FROM generate_series(1, 50) AS n
ON CONFLICT DO NOTHING;

INSERT INTO aliado_categoria (id, tenant_id, aliado_id, categoria_id)
SELECT ('80000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       '10000000-0000-4000-8000-000000000011',
       ('50000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       '60000000-0000-4000-8000-000000000011'   -- Plomeria
  FROM generate_series(1, 50) AS n
ON CONFLICT DO NOTHING;

INSERT INTO cobertura_aliado (id, tenant_id, aliado_id, zona_id)
SELECT ('90000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       '10000000-0000-4000-8000-000000000011',
       ('50000000-0000-4000-8000-00000000' || '61' || lpad(n::text, 2, '0'))::uuid,
       '20000000-0000-4000-8000-000000000002'   -- Chapinero
  FROM generate_series(1, 50) AS n
ON CONFLICT DO NOTHING;

COMMIT;

-- Siguiente paso: correr supabase/seed/verificar_siembra_sprint5.sql.
