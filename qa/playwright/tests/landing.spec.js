// SCRUM-1335 (US-09.1.1): landing comercial como entrada publica a la plataforma.
const { test, expect } = require('@playwright/test');
const { url_landing } = require('./datos_qa');

test.describe('SCRUM-1335 Landing comercial', () => {
  test('1335-01 carga la landing y muestra las tarifas base', async ({ page }) => {
    const respuesta = await page.goto(url_landing);
    expect(respuesta.status()).toBe(200);
    await expect(page.locator('h1').first()).toBeVisible();
    const tarifas = page.locator('[data-testid^="tarifa-"]');
    await expect(tarifas.first()).toBeVisible();
    expect(await tarifas.count()).toBeGreaterThanOrEqual(3);
    await expect(page.getByTestId('tarifa-plomeria')).toContainText('$');
  });

  test('1335-02 el estimador muestra un rango y el aviso de estimacion', async ({ page }) => {
    await page.goto(url_landing);
    await page.getByRole('button', { name: /Solicitar Servicio/i }).first().click();
    await expect(page.getByTestId('rango-estimado')).toBeVisible();
    await expect(page.getByTestId('rango-estimado')).toContainText('$');
    await expect(page.getByTestId('aviso-estimacion')).toBeVisible();
  });

  test('1335-03 el boton de ingreso lleva a Flutter Web', async ({ page }) => {
    await page.goto(url_landing);
    const [destino] = await Promise.all([
      page.context().waitForEvent('page', { timeout: 10_000 }).catch(() => null),
      page.getByText(/Ingresar a MANI Web/i).first().click(),
    ]);
    expect(destino, 'el boton debe abrir Flutter Web en una pestana nueva').not.toBeNull();
    await destino.waitForURL(/:8080/, { timeout: 15_000 });
    expect(new URL(destino.url()).port).toBe('8080');
  });
});
