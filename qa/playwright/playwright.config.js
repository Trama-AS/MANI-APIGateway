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
    extraHTTPHeaders: { 'X-Correlation-ID': `qa1267-pw-${Date.now()}` },
  },
  outputDir: 'artefactos',
});
