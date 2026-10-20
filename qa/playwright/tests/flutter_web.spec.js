// Flutter Web en QA: carga y configuracion de ambiente (Supabase de QA y Gateway).
// Revisa el .env que flutter_dotenv empaqueta en assets sin imprimir llaves: solo hosts.
const { test, expect } = require('@playwright/test');
const { url_flutter, datos } = require('./datos_qa');

function hostDe(env, clave) {
  const linea = env.split('\n').find((l) => l.startsWith(`${clave}=`)) || '';
  try {
    return new URL(linea.split('=').slice(1).join('=').trim()).host;
  } catch {
    return '';
  }
}

test.describe('Flutter Web en QA', () => {
  test('FW-01 la aplicacion carga y arranca el motor de Flutter', async ({ page }) => {
    const respuesta = await page.goto(url_flutter);
    expect(respuesta.status()).toBe(200);
    await expect(page.locator('flutter-view, flt-glass-pane').first()).toBeAttached({ timeout: 30_000 });
  });

  test('FW-02 la imagen de QA apunta al Supabase de MANI-QA', async ({ request }) => {
    const respuesta = await request.get(`${url_flutter}/assets/.env`);
    expect(respuesta.status()).toBe(200);
    const host = hostDe(await respuesta.text(), 'SUPABASE_URL');
    test.info().annotations.push({ type: 'supabase_host', description: host });
    expect(host).toContain(datos.ref_supabase_qa);
  });

  test('FW-03 la imagen de QA apunta al Gateway de QA y no a localhost', async ({ request }) => {
    const respuesta = await request.get(`${url_flutter}/assets/.env`);
    const host = hostDe(await respuesta.text(), 'API_GATEWAY_URL');
    test.info().annotations.push({ type: 'gateway_host', description: host || 'sin definir' });
    expect(host).not.toMatch(/^(localhost|127\.0\.0\.1)(:\d+)?$/);
  });
});
