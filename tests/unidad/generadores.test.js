const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const RAIZ = path.join(__dirname, '..', '..');
const COLECCION_CORE = path.join(RAIZ, 'postman', 'MANI-Core.postman_collection.json');
const COLECCION_RULES = path.join(RAIZ, 'postman', 'MANI-Rules.postman_collection.json');
const COLECCION_QA = path.join(RAIZ, 'qa', 'newman', 'mani_regresion_sprint4.postman_collection.json');

/** Carga un generador sin dejarle tocar el disco y devuelve lo que habría escrito. */
function generar(t, script) {
  const ruta = path.join(RAIZ, script);
  delete require.cache[ruta];
  t.mock.method(console, 'log', () => {});
  return new Promise((listo) => {
    t.mock.method(fs, 'writeFileSync', (salida, contenido) => listo({ salida, contenido }));
    require(ruta);
  });
}

function ejecutar(script, ...argumentos) {
  return spawnSync(process.execPath, [path.join(RAIZ, script), ...argumentos], {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
}

function peticiones(nodo) {
  return nodo.item ? nodo.item.flatMap(peticiones) : [`${nodo.request.method} ${nodo.name}`];
}

test('la colección de Rules versionada es la que produce su generador', async (t) => {
  const { salida, contenido } = await generar(t, 'scripts/generate-rules-collection.js');
  assert.equal(salida, COLECCION_RULES);
  assert.equal(contenido, fs.readFileSync(COLECCION_RULES, 'utf8'));
});

test('la colección de regresión de QA versionada es la que produce su generador', async (t) => {
  const { salida, contenido } = await generar(t, 'qa/newman/generar_coleccion.js');
  assert.equal(salida, COLECCION_QA);
  assert.equal(contenido, fs.readFileSync(COLECCION_QA, 'utf8'));
});

// El conversor elige al azar algunos ejemplos, así que se compara qué peticiones y pruebas contiene.
test('la colección de Core versionada tiene las peticiones del contrato', async (t) => {
  const { salida, contenido } = await generar(t, 'scripts/generate-postman-collection.js');
  const generada = JSON.parse(contenido);
  assert.equal(salida, COLECCION_CORE);
  assert.deepEqual(peticiones(generada), peticiones(JSON.parse(fs.readFileSync(COLECCION_CORE, 'utf8'))));
  assert.match(contenido, /propagación del claim de tenant/);
});

test('todos los contratos son OpenAPI válido', () => {
  const { status, stdout } = ejecutar('scripts/validate-openapi.js');
  assert.equal(status, 0);
  assert.equal(stdout.match(/✔ OpenAPI válido/g).length, 4);
});

test('el SQL de geometrías va en una transacción y solo crea zonas si se pide', () => {
  const normal = ejecutar('scripts/cargar-geometrias.js');
  const con_zonas = ejecutar('scripts/cargar-geometrias.js', '--crear-zonas');
  assert.equal(normal.status, 0);
  assert.ok(normal.stdout.includes('\nBEGIN;\n'));
  assert.ok(normal.stdout.endsWith('COMMIT;\n'));
  assert.match(normal.stdout, /ON CONFLICT \(zona_id\) DO UPDATE/);
  assert.ok(!normal.stdout.includes('INSERT INTO zona ('));
  assert.ok(con_zonas.stdout.includes('INSERT INTO zona ('));
});
