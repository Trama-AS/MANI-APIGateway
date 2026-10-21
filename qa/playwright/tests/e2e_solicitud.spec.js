// Recorrido E2E obligatorio de SCRUM-1267: crear solicitud -> aliados elegibles -> despacho -> aceptacion.
// Historias: SCRUM-1072, SCRUM-861, SCRUM-862, SCRUM-1073, SCRUM-1074 (y control cross-tenant).
// Pasa por el API Gateway real de QA con la base MANI-QA. Cada paso queda en el trace de Playwright.
const crypto = require('node:crypto');
const { test, expect } = require('@playwright/test');
const { url_gateway, datos, cabeceras } = require('./datos_qa');

const core = `${url_gateway}/api/v1/core`;
const dispatch = `${url_gateway}/api/v1/dispatch`;

test.describe.configure({ mode: 'serial' });
test.describe('E2E solicitud de servicio en QA', () => {
  let solicitud_id;

  test('E2E-01 SCRUM-1072 el cliente t1 crea la solicitud en su sitio', async ({ request }) => {
    const respuesta = await request.post(`${core}/solicitudes`, {
      headers: cabeceras('cliente_t1'),
      data: {
        categoriaId: datos.categoria_t1,
        descripcion: `Fuga en la cocina, recorrido E2E SCRUM-1267 ${Date.now()}`,
        sitioId: datos.sitio_t1,
        claveIdempotencia: crypto.randomUUID(),
      },
    });
    const cuerpo = await respuesta.text();
    test.info().annotations.push({ type: 'respuesta', description: `${respuesta.status()} ${cuerpo.slice(0, 200)}` });
    expect(respuesta.status()).toBe(201);
    const json = JSON.parse(cuerpo);
    solicitud_id = (json.solicitud && json.solicitud.id) || json.id;
    expect(solicitud_id).toMatch(/^[0-9a-f-]{36}$/);
  });

  test('E2E-02 SCRUM-861/862 Dispatch encuentra al aliado t1 por cobertura, categoria y tipo', async ({ request }) => {
    test.skip(!solicitud_id, 'sin solicitud creada en E2E-01');
    const respuesta = await request.get(
      `${dispatch}/requests/${solicitud_id}/eligible-allies?zonaId=${datos.zona_cobertura}&categoriaId=${datos.categoria_t1}&tipo=PERSONA_NATURAL`,
      { headers: cabeceras('admin_t1') },
    );
    const cuerpo = await respuesta.text();
    test.info().annotations.push({ type: 'respuesta', description: `${respuesta.status()} ${cuerpo.slice(0, 200)}` });
    expect(respuesta.status()).toBe(200);
    expect(cuerpo).toContain(datos.aliado_t1);
    expect(cuerpo).not.toContain(datos.aliado_t2);
  });

  test('E2E-03 SCRUM-1073 Dispatch orquesta el despacho', async ({ request }) => {
    test.skip(!solicitud_id, 'sin solicitud creada en E2E-01');
    const respuesta = await request.post(`${dispatch}/requests/orchestrate`, {
      headers: cabeceras('admin_t1'),
      data: { requestId: solicitud_id },
    });
    const cuerpo = await respuesta.text();
    test.info().annotations.push({ type: 'respuesta', description: `${respuesta.status()} ${cuerpo.slice(0, 200)}` });
    expect([200, 201, 202]).toContain(respuesta.status());
  });

  test('E2E-04 SCRUM-1074 el aliado t1 acepta y la reaceptacion es idempotente', async ({ request }) => {
    test.skip(!solicitud_id, 'sin solicitud creada en E2E-01');
    const primera = await request.post(`${dispatch}/requests/${solicitud_id}/accept`, { headers: cabeceras('aliado_t1') });
    const segunda = await request.post(`${dispatch}/requests/${solicitud_id}/accept`, { headers: cabeceras('aliado_t1') });
    test.info().annotations.push({ type: 'respuesta', description: `primera ${primera.status()} segunda ${segunda.status()}` });
    expect(primera.status()).toBe(200);
    expect(segunda.status()).toBe(200);
    expect(await segunda.text()).toContain(datos.aliado_t1);
  });

  test('E2E-05 Cross-tenant: el aliado t2 no puede aceptar la solicitud de t1', async ({ request }) => {
    test.skip(!solicitud_id, 'sin solicitud creada en E2E-01');
    const respuesta = await request.post(`${dispatch}/requests/${solicitud_id}/accept`, { headers: cabeceras('aliado_t2') });
    test.info().annotations.push({ type: 'respuesta', description: String(respuesta.status()) });
    expect([403, 404, 409]).toContain(respuesta.status());
  });
});
