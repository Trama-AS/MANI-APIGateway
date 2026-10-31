-- =====================================================================
-- MANI — Verificación de la semilla de QA del Sprint 5
-- =====================================================================
-- Ticket: SCRUM-1463 (TEC-16)
-- Complemento de: supabase/seed/seed_qa_sprint5.sql
--
-- SOLO LECTURA. Abre una transacción, crea una vista temporal con los
-- chequeos, la muestra y termina en ROLLBACK. Si algún chequeo no da lo
-- esperado, el bloque final falla con la lista de los que no pasaron.
--
-- CÓMO SE CORRE
--   psql "$URL_QA" -f supabase/seed/verificar_siembra_sprint5.sql
--
-- QUÉ REVISA
--   1. Elegibles del broadcast: 51 aliados en el Tenant 1 para Plomería y
--      Chapinero, con la misma condición de
--      MANI-Node/src/infrastructure/repositories/PgElegibilidadRepository.js
--      (FIND_ELIGIBLE_SQL, sin exclusiones ni filtro de tipo).
--   2. Una cuenta real de GoTrue por tipo y tenant: auth.users con identity,
--      claims del tenant correcto y fila en usuario ACTIVO con el rol en
--      mayúscula.
--   3. Cada barrio con su padre: LOCALIDAD activa existente.
--   4. Categorías y tarifas: 2 activas y 1 inactiva por tenant, cada activa
--      con tarifa coherente (valor_min <= valor_tipico <= valor_max).
--   5. Nada cruzado entre tenants.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP VIEW chequeo_sprint5 AS
WITH RECURSIVE
tenants (tenant_id, tenant) AS (
  VALUES ('10000000-0000-4000-8000-000000000011'::uuid, 't1'),
         ('10000000-0000-4000-8000-000000000021'::uuid, 't2')
),

-- 1. Copia de FIND_ELIGIBLE_SQL con $1 = Tenant 1, $2 = Plomería,
--    $3 = Chapinero, $4 = NULL y $5 = '{}'.
ascendencia AS (
  SELECT z.id, z.zona_padre_id, 1 AS nivel FROM zona z WHERE z.id = '20000000-0000-4000-8000-000000000002'
  UNION ALL
  SELECT z.id, z.zona_padre_id, a.nivel + 1
  FROM zona z JOIN ascendencia a ON z.id = a.zona_padre_id
  WHERE a.nivel < 10
),
elegibles AS (
  SELECT DISTINCT a.id, a.nombre_razon_social, a.tipo, a.estado_verificacion
  FROM aliado a
  JOIN usuario u ON u.id = a.usuario_id AND u.tenant_id = a.tenant_id AND u.estado = 'ACTIVO'
  JOIN aliado_categoria ac ON ac.aliado_id = a.id AND ac.tenant_id = a.tenant_id
  JOIN categoria_servicio cs ON cs.id = ac.categoria_id AND cs.tenant_id = a.tenant_id AND cs.estado = 'ACTIVO'
  JOIN cobertura_aliado ca ON ca.aliado_id = a.id AND ca.tenant_id = a.tenant_id
  JOIN ascendencia asc_z ON asc_z.id = ca.zona_id
  JOIN zona z ON z.id = ca.zona_id AND upper(btrim(coalesce(z.estado, ''))) IN ('ACTIVO', 'ACTIVA')
  WHERE a.tenant_id = '10000000-0000-4000-8000-000000000011'
    AND ac.categoria_id = '60000000-0000-4000-8000-000000000011'
    AND a.estado_verificacion = 'VERIFICADO'
    AND NOT EXISTS (
      SELECT 1 FROM aliado_ausencia aa
      WHERE aa.aliado_id = a.id AND aa.tenant_id = a.tenant_id
        AND aa.inicio <= now() AND aa.fin > now()
    )
),

-- 2. Cuentas que pueden iniciar sesión, con su tipo de cuenta.
cuentas AS (
  SELECT u.tenant_id,
         CASE
           WHEN u.rol = 'ADMIN_TENANT'                                        THEN 'admin_tenant'
           WHEN u.rol = 'CLIENTE' AND c.tipo = 'PERSONA_NATURAL'              THEN 'cliente_natural'
           WHEN u.rol = 'CLIENTE' AND c.tipo = 'PERSONA_JURIDICA'
                AND c.razon_social IS NOT NULL AND c.nit IS NOT NULL
                AND (SELECT count(*) FROM sitio s WHERE s.cliente_id = c.id) >= 2 THEN 'cliente_empresa'
           WHEN u.rol = 'ALIADO' AND a.estado_verificacion = 'VERIFICADO'
                AND EXISTS (SELECT 1 FROM aliado_categoria ac WHERE ac.aliado_id = a.id)
                AND EXISTS (SELECT 1 FROM cobertura_aliado ca WHERE ca.aliado_id = a.id) THEN
             CASE a.tipo
               WHEN 'PERSONA_NATURAL'  THEN 'aliado_natural'
               WHEN 'PERSONA_JURIDICA' THEN 'aliado_empresa'
               WHEN 'EMPLEADO_DIRECTO' THEN 'empleado_directo'
             END
         END AS tipo_cuenta
    FROM auth.users au
    JOIN usuario u ON u.id = au.id AND u.estado = 'ACTIVO'
    LEFT JOIN cliente c ON c.usuario_id = u.id
    LEFT JOIN aliado  a ON a.usuario_id = u.id
   WHERE au.email_confirmed_at IS NOT NULL
     AND au.encrypted_password IS NOT NULL
     AND au.confirmation_token IS NOT NULL
     AND EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = au.id)
     AND au.raw_app_meta_data ->> 'tenant_id' = u.tenant_id::text
     AND au.raw_app_meta_data ->> 'user_role' = lower(u.rol)
),
tipos_cuenta (tipo_cuenta) AS (
  VALUES ('admin_tenant'), ('cliente_natural'), ('cliente_empresa'),
         ('aliado_natural'), ('aliado_empresa'), ('empleado_directo')
),

-- 5. Filas relacionadas con tenant_id distinto.
cruces AS (
  SELECT 'cliente -> usuario' AS relacion, c.id FROM cliente c
    JOIN usuario u ON u.id = c.usuario_id WHERE u.tenant_id IS DISTINCT FROM c.tenant_id
  UNION ALL
  SELECT 'aliado -> usuario', a.id FROM aliado a
    JOIN usuario u ON u.id = a.usuario_id WHERE u.tenant_id IS DISTINCT FROM a.tenant_id
  UNION ALL
  SELECT 'aliado -> verificado_por', a.id FROM aliado a
    JOIN usuario u ON u.id = a.verificado_por WHERE u.tenant_id IS DISTINCT FROM a.tenant_id
  UNION ALL
  SELECT 'sitio -> cliente', s.id FROM sitio s
    JOIN cliente c ON c.id = s.cliente_id WHERE c.tenant_id IS DISTINCT FROM s.tenant_id
  UNION ALL
  SELECT 'aliado_categoria -> aliado', ac.id FROM aliado_categoria ac
    JOIN aliado a ON a.id = ac.aliado_id WHERE a.tenant_id IS DISTINCT FROM ac.tenant_id
  UNION ALL
  SELECT 'aliado_categoria -> categoria', ac.id FROM aliado_categoria ac
    JOIN categoria_servicio cs ON cs.id = ac.categoria_id WHERE cs.tenant_id IS DISTINCT FROM ac.tenant_id
  UNION ALL
  SELECT 'cobertura_aliado -> aliado', ca.id FROM cobertura_aliado ca
    JOIN aliado a ON a.id = ca.aliado_id WHERE a.tenant_id IS DISTINCT FROM ca.tenant_id
  UNION ALL
  SELECT 'tarifa_referencia -> categoria', t.id FROM tarifa_referencia t
    JOIN categoria_servicio cs ON cs.id = t.categoria_id WHERE cs.tenant_id IS DISTINCT FROM t.tenant_id
  UNION ALL
  SELECT 'categoria_servicio -> creado_por', cs.id FROM categoria_servicio cs
    JOIN usuario u ON u.id = cs.creado_por WHERE u.tenant_id IS DISTINCT FROM cs.tenant_id
  UNION ALL
  SELECT 'auth.users -> usuario (claim tenant_id)', au.id FROM auth.users au
    JOIN usuario u ON u.id = au.id
   WHERE au.raw_app_meta_data ->> 'tenant_id' IS DISTINCT FROM u.tenant_id::text
)

SELECT 1 AS orden, 'elegibles t1 plomeria chapinero' AS chequeo, '= 51' AS esperado,
       (SELECT count(*) FROM elegibles)::text AS obtenido,
       (SELECT count(*) FROM elegibles) = 51 AS ok
UNION ALL
SELECT 2, 'elegibles incluye aliado de cfg-04 (50…011)', 'true',
       (SELECT count(*) > 0 FROM elegibles WHERE id = '50000000-0000-4000-8000-000000000011')::text,
       (SELECT count(*) > 0 FROM elegibles WHERE id = '50000000-0000-4000-8000-000000000011')
UNION ALL
SELECT 3, 'cuentas ' || t.tenant || ' ' || tc.tipo_cuenta, '>= 1',
       (SELECT count(*) FROM cuentas c WHERE c.tenant_id = t.tenant_id AND c.tipo_cuenta = tc.tipo_cuenta)::text,
       (SELECT count(*) FROM cuentas c WHERE c.tenant_id = t.tenant_id AND c.tipo_cuenta = tc.tipo_cuenta) >= 1
  FROM tenants t CROSS JOIN tipos_cuenta tc
UNION ALL
SELECT 4, 'barrios bajo ' || p.nombre, '>= 2',
       (SELECT count(*) FROM zona b WHERE b.nivel = 'BARRIO' AND b.zona_padre_id = p.id AND b.estado = 'ACTIVO')::text,
       (SELECT count(*) FROM zona b WHERE b.nivel = 'BARRIO' AND b.zona_padre_id = p.id AND b.estado = 'ACTIVO') >= 2
  FROM zona p
 WHERE p.id IN ('20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000003')
UNION ALL
SELECT 5, 'barrios sin padre localidad activa', '= 0',
       count(*)::text, count(*) = 0
  FROM zona b
  LEFT JOIN zona p ON p.id = b.zona_padre_id
 WHERE b.nivel = 'BARRIO'
   AND (p.id IS NULL OR p.nivel <> 'LOCALIDAD' OR p.estado <> 'ACTIVO')
UNION ALL
SELECT 6, 'categorias activas ' || t.tenant, '>= 2',
       (SELECT count(*) FROM categoria_servicio cs WHERE cs.tenant_id = t.tenant_id AND cs.estado = 'ACTIVO')::text,
       (SELECT count(*) FROM categoria_servicio cs WHERE cs.tenant_id = t.tenant_id AND cs.estado = 'ACTIVO') >= 2
  FROM tenants t
UNION ALL
SELECT 7, 'categorias inactivas ' || t.tenant, '>= 1',
       (SELECT count(*) FROM categoria_servicio cs WHERE cs.tenant_id = t.tenant_id AND cs.estado = 'INACTIVO')::text,
       (SELECT count(*) FROM categoria_servicio cs WHERE cs.tenant_id = t.tenant_id AND cs.estado = 'INACTIVO') >= 1
  FROM tenants t
UNION ALL
SELECT 8, 'categorias activas sin tarifa ' || t.tenant, '= 0',
       (SELECT count(*) FROM categoria_servicio cs
         WHERE cs.tenant_id = t.tenant_id AND cs.estado = 'ACTIVO'
           AND NOT EXISTS (SELECT 1 FROM tarifa_referencia tr
                            WHERE tr.categoria_id = cs.id AND tr.tenant_id = cs.tenant_id))::text,
       (SELECT count(*) FROM categoria_servicio cs
         WHERE cs.tenant_id = t.tenant_id AND cs.estado = 'ACTIVO'
           AND NOT EXISTS (SELECT 1 FROM tarifa_referencia tr
                            WHERE tr.categoria_id = cs.id AND tr.tenant_id = cs.tenant_id)) = 0
  FROM tenants t
UNION ALL
SELECT 9, 'tarifas con rango invalido', '= 0',
       count(*)::text, count(*) = 0
  FROM tarifa_referencia tr
 WHERE tr.tenant_id IN (SELECT tenant_id FROM tenants)
   AND NOT (tr.valor_min > 0 AND tr.valor_min <= tr.valor_tipico AND tr.valor_tipico <= tr.valor_max)
UNION ALL
SELECT 10, 'cruces entre tenants', '= 0',
       count(*)::text || coalesce(' (' || string_agg(DISTINCT relacion, ', ') || ')', ''),
       count(*) = 0
  FROM cruces;

SELECT chequeo, esperado, obtenido, ok FROM chequeo_sprint5 ORDER BY orden, chequeo;

DO $$
DECLARE
  v_fallos text;
BEGIN
  SELECT string_agg(chequeo || ' (obtenido ' || obtenido || ', esperado ' || esperado || ')', '; ' ORDER BY orden, chequeo)
    INTO v_fallos
    FROM chequeo_sprint5
   WHERE NOT ok;

  IF v_fallos IS NOT NULL THEN
    RAISE EXCEPTION 'La semilla del Sprint 5 no pasa: %', v_fallos;
  END IF;

  RAISE NOTICE 'Semilla del Sprint 5 verificada: todos los chequeos pasan.';
END $$;

ROLLBACK;
