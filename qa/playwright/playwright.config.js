// Configuracion de Playwright para la regresion del Sprint 4 en QA (SCRUM-1278).
// Las URLs se toman del entorno para correr dentro de la VM de QA (localhost) o desde Calidad.
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests',
  timeout: 60_000,
  retries: 0,
  workers: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'reporte_html', open: 'never' }],
    ['json', { outputFile: 'resultados.json' }],
  ],
  use: {
    trace: 'on',
    screenshot: 'on',
    video: 'retain-on-failure',
    // Sin extraHTTPHeaders globales: un encabezado personalizado en todas las peticiones del navegador
    // provoca preflight CORS contra el CDN de Google (CanvasKit y fuentes) y Flutter Web no arranca.
  },
  outputDir: 'artefactos',
});
