// Smoke de ambiente con una cuenta real (QA o PROD, despues de cada despliegue).
// La regresion usa tokens HS256 sinteticos: no detecta un hook de claims apagado, un Supabase distinto
// en la imagen de Flutter ni que Core o Dispatch rechacen el token real (PROD, 22 oct 2026).
// Supabase URL y anon key se leen del /assets/.env publicado por Flutter: se prueba la misma
// configuracion que usa el navegador. Credenciales por entorno (SMOKE_EMAIL, SMOKE_PASSWORD);
// opcional SMOKE_TENANT_ID para exigir el tenant esperado. No se imprimen tokens ni llaves.
const { test, expect } = require('@playwright/test');
const { url_gateway, url_flutter } = require('./datos_qa');

const email = process.env.SMOKE_EMAIL;
const password = process.env.SMOKE_PASSWORD;
const tenant_esperado = process.env.SMOKE_TENANT_ID;
const roles = ['ADMIN_TENANT', 'CLIENTE', 'ALIADO', 'SUPER_ADMIN'];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function valorEnv(env, clave) {
  const linea = env.split('\n').find((l) => l.startsWith(`${clave}=`)) || '';
  return linea.split('=').slice(1).join('=').trim();
}

function cargaJwt(token) {
  return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
}

test.describe.configure({ mode: 'serial' });
test.describe('Smoke de ambiente con cuenta real', () => {
  let access_token;

  test('SMK-01 Gateway, Core, Rules y Dispatch responden health', async ({ request }) => {
    for (const ruta of ['/health', '/api/v1/core/health', '/api/v1/rules/health', '/api/v1/dispatch/health']) {
      const respuesta = await request.get(`${url_gateway}${ruta}`);
      expect(respuesta.status(), ruta).toBe(200);
    }
  });

  test('SMK-02 login real en el Supabase que usa la app publicada', async ({ request }) => {
    test.skip(!email || !password, 'definir SMOKE_EMAIL y SMOKE_PASSWORD');
    const env = await (await request.get(`${url_flutter}/assets/.env`)).text();
    const supabase_url = valorEnv(env, 'SUPABASE_URL');
    const anon = valorEnv(env, 'SUPABASE_ANON_KEY');
    expect(supabase_url, 'SUPABASE_URL en /assets/.env de Flutter').toMatch(/^https?:\/\//);
    test.info().annotations.push({ type: 'supabase_host', description: new URL(supabase_url).host });

    const respuesta = await request.post(`${supabase_url}/auth/v1/token?grant_type=password`, {
      headers: { apikey: anon, 'Content-Type': 'application/json' },
      data: { email, password },
    });
    expect(respuesta.status(), 'login con la cuenta de smoke').toBe(200);
    access_token = (await respuesta.json()).access_token;
    expect(access_token).toBeTruthy();
  });

  test('SMK-03 el token real trae tenant_id y user_role (hook de claims activo)', async () => {
    test.skip(!access_token, 'sin token de SMK-02');
    const carga = cargaJwt(access_token);
    const meta = carga.app_metadata || {};
    test.info().annotations.push({ type: 'claims', description: `alg=${JSON.parse(Buffer.from(access_token.split('.')[0], 'base64url')).alg} rol=${meta.user_role}` });
    expect(meta.tenant_id, 'app_metadata.tenant_id').toMatch(uuid);
    expect(roles, 'app_metadata.user_role').toContain(meta.user_role);
    if (tenant_esperado) expect(meta.tenant_id).toBe(tenant_esperado);
  });

  test('SMK-04 Core acepta el token real (GET /profiles/me)', async ({ request }) => {
    test.skip(!access_token, 'sin token de SMK-02');
    const respuesta = await request.get(`${url_gateway}/api/v1/core/profiles/me`, {
      headers: { Authorization: `Bearer ${access_token}`, 'X-Correlation-ID': `smoke-${Date.now()}` },
    });
    test.info().annotations.push({ type: 'respuesta', description: String(respuesta.status()) });
    expect(respuesta.status()).toBe(200);
  });

  test('SMK-05 Dispatch acepta el token real (no responde 401)', async ({ request }) => {
    test.skip(!access_token, 'sin token de SMK-02');
    const respuesta = await request.get(`${url_gateway}/api/v1/dispatch/assignments/me`, {
      headers: { Authorization: `Bearer ${access_token}`, 'X-Correlation-ID': `smoke-${Date.now()}` },
    });
    test.info().annotations.push({ type: 'respuesta', description: String(respuesta.status()) });
    // 403 es valido si la cuenta no es aliado: lo que se prueba es que el token se valida.
    expect(respuesta.status()).not.toBe(401);
    expect(respuesta.status()).toBeLessThan(500);
  });
});
