// Preflight CORS del Gateway desplegado para el origen de Flutter Web.
// Newman y los casos con `request` no envian Origin ni hacen preflight: por eso el Gateway de PROD
// bloqueaba Idempotency-Key en "Publicar solicitud" con la regresion en verde (22 oct 2026).
// Los encabezados son los que agrega MANI-Flutter (lib/core/network/gateway_client.dart y datasources).
const { test, expect } = require('@playwright/test');
const { url_gateway, url_flutter } = require('./datos_qa');

const origen = new URL(url_flutter).origin;
const base = ['authorization', 'content-type', 'x-correlation-id'];

const casos = [
  { id: 'CORS-01', metodo: 'POST', ruta: '/api/v1/core/solicitudes', encabezados: [...base, 'idempotency-key'] },
  { id: 'CORS-02', metodo: 'POST', ruta: '/api/v1/core/auth/register/client', encabezados: ['content-type', 'x-correlation-id', 'x-tenant-slug'] },
  { id: 'CORS-03', metodo: 'POST', ruta: '/api/v1/core/auth/register/ally', encabezados: ['content-type', 'x-correlation-id', 'x-tenant-slug'] },
  { id: 'CORS-04', metodo: 'GET', ruta: '/api/v1/core/legal/documents/active', encabezados: ['x-correlation-id', 'x-tenant-slug'] },
  { id: 'CORS-05', metodo: 'POST', ruta: '/api/v1/core/legal/consents', encabezados: base },
  { id: 'CORS-06', metodo: 'GET', ruta: '/api/v1/core/profiles/me', encabezados: base },
  { id: 'CORS-07', metodo: 'GET', ruta: '/api/v1/dispatch/assignments/me', encabezados: base },
];

test.describe('Preflight CORS del Gateway para Flutter Web', () => {
  for (const caso of casos) {
    test(`${caso.id} OPTIONS ${caso.metodo} ${caso.ruta}`, async ({ request }) => {
      const respuesta = await request.fetch(`${url_gateway}${caso.ruta}`, {
        method: 'OPTIONS',
        headers: {
          Origin: origen,
          'Access-Control-Request-Method': caso.metodo,
          'Access-Control-Request-Headers': caso.encabezados.join(','),
        },
      });
      const h = respuesta.headers();
      const permitidos = (h['access-control-allow-headers'] || '').toLowerCase().split(',').map((x) => x.trim());
      const metodos = (h['access-control-allow-methods'] || '').toUpperCase();
      test.info().annotations.push({ type: 'allow-headers', description: h['access-control-allow-headers'] || 'sin encabezado' });

      expect([200, 204]).toContain(respuesta.status());
      expect(['*', origen]).toContain(h['access-control-allow-origin']);
      expect(metodos).toContain(caso.metodo);
      expect(caso.encabezados.filter((e) => !permitidos.includes(e)), 'encabezados que el navegador bloquearia').toEqual([]);
    });
  }
});
