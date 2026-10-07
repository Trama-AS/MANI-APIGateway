-- =====================================================================
-- 008 · US-02.1.1-M2 — Soporte para el registro de Aliado persona natural
-- migrado a Core Node (ADR-0022).
--
-- El contrato OpenAPI de CFG-16 (docs/openapi/core.yaml en este repo) acepta
-- phone/documentType/documentNumber como opcionales en el registro, pero el
-- esquema original (database/init/01-schema.sql) no tenía columnas para
-- persistirlos si se envían. Esta migración las agrega.
--
-- Idempotente: reaplicarla no cambia nada (IF NOT EXISTS / conflict check).
-- =====================================================================

-- 0. Tabla de control (por si el entorno no corrió 001) ----------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE usuario ADD COLUMN IF NOT EXISTS telefono TEXT;

ALTER TABLE aliado ADD COLUMN IF NOT EXISTS tipo_documento_identidad TEXT;
ALTER TABLE aliado ADD COLUMN IF NOT EXISTS numero_documento_identidad TEXT;

-- Múltiples NULL no violan UNIQUE en Postgres, así que los aliados ya
-- existentes (sin este dato, porque Flutter no lo recolecta todavía) no se
-- ven afectados.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'aliado_numero_documento_identidad_tenant_unique'
    ) THEN
        ALTER TABLE aliado
            ADD CONSTRAINT aliado_numero_documento_identidad_tenant_unique
            UNIQUE (tenant_id, numero_documento_identidad);
    END IF;
END $$;

-- Registro de la migración ---------------------------------------------------
INSERT INTO schema_migrations (version, description)
VALUES ('008', 'US-02.1.1-M2 registro de aliado en Core Node: telefono (usuario) y tipo/numero_documento_identidad (aliado)')
ON CONFLICT (version) DO NOTHING;

-- =====================================================================
-- IMPORTANTE — acción manual pendiente, NO incluida en esta migración:
--
-- Ahora que Core Node (MANI-Node/src/application/useCases/auth/
-- RegisterAllyNaturalPersonUseCase.js) ejecuta explícitamente la lógica de
-- registrar_aliado_persona_natural / handle_new_user, el trigger
-- `on_auth_user_created` sobre `auth.users` (función handle_new_user,
-- database/init/05-supabase-complete-sync.sql) queda DUPLICADO: si sigue
-- activo, se dispara también cuando Core Node llama
-- client.auth.admin.createUser(), insertando/actualizando usuario y aliado
-- una segunda vez (benigno gracias a los ON CONFLICT, pero redundante y una
-- fuente de confusión/condiciones de carrera a futuro).
--
-- Se recomienda, una vez validado que Core Node funciona end-to-end en QA:
--
--   DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
--
-- No se incluye ese DROP aquí para no desactivar el único mecanismo de
-- creación de usuario/aliado mientras el flujo de Core Node no esté
-- validado en QA.
-- =====================================================================
