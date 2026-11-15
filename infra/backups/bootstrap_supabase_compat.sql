-- Compatibilidad minima de Supabase para simulacros de restauracion aislados (SCRUM-1666)
-- Permite restaurar volcados del esquema public en una instancia PostgreSQL 17 independiente
-- sin tocar las bases compartidas de QA o PROD.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS vault;

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- Asegura que funciones en public que omitan prefijo resuelvan extensions.*
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET search_path TO public, extensions', current_database());
END $$;

DO $$
DECLARE
  role_name TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY[
    'anon',
    'authenticated',
    'service_role',
    'authenticator',
    'supabase_admin',
    'supabase_auth_admin',
    'dashboard_user',
    'mani_core_svc',
    'mani_dispatch_svc',
    'mani_rules_svc'
  ]
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', role_name);
    END IF;
  END LOOP;
END $$;

-- Funciones stub de auth para compilar politicas RLS y RPCs durante el simulacro
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
