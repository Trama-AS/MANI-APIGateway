const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const http = require('node:http');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { cargarContrato } = require('../../scripts/contrato/operaciones');
const { firmarToken, verificarContrato } = require('../../scripts/contrato/verificar');
const { informe, leerOpciones, principal } = require('../../scripts/verificar-contrato');

const CONTRATO = path.join(__dirname, 'contrato.yaml');
const CLI = path.join(__dirname, '..', '..', 'scripts', 'verificar-contrato.js');
const SECRETO = 'secreto_solo_para_pruebas_unitarias';

const json = (estado, cuerpo) => ({ estado, tipo: 'application/json; charset=utf-8', cuerpo: JSON.stringify(cuerpo) });

// Servicio que cumple el contrato de prueba; cada prueba cambia una sola respuesta.
const RESPUESTAS = {
  'GET /salud': () => json(200, { estado: 'ok' }),
  'POST /nodos': ({ sesion, cuerpo }) => {
    if (!sesion) return json(401, { code: 'UNAUTHORIZED' });
    return cuerpo.nombre ? json(201, { nombre: cuerpo.nombre, hijos: [{ nombre: 'x' }] }) : json(400, { code: 'VALIDATION_ERROR' });
  },
  'POST /fotos': () => json(400, { code: 'VALIDATION_ERROR' }),
  'GET /texto': () => ({ estado: 200, tipo: 'text/plain', cuerpo: 'hola' }),
};

async function verificarServicio(cambios = {}) {
  const respuestas = { ...RESPUESTAS, ...cambios };
  const recibidas = [];
  const servidor = http.createServer(async (req, res) => {
    const partes = [];
    for await (const parte of req) partes.push(parte);
    const texto = Buffer.concat(partes).toString();
    recibidas.push(`${req.method} ${req.url}`);
    const ruta = respuestas[`${req.method} /${new URL(req.url, 'http://localhost').pathname.split('/')[1]}`];
    const { estado, tipo, cuerpo } = ruta
      ? ruta({ sesion: Boolean(req.headers.authorization), cuerpo: texto ? JSON.parse(texto) : {} })
      : json(404, { error: 'Ruta no encontrada', correlationId: randomUUID() });
    res.writeHead(estado, { 'content-type': tipo });
    res.end(cuerpo);
  });
  await new Promise((listo) => { servidor.listen(0, '127.0.0.1', listo); });
  try {
    const cargado = await cargarContrato(CONTRATO);
    const base = `http://127.0.0.1:${servidor.address().port}/`;
    const resultados = await verificarContrato({ ...cargado, base, roles: ['cliente'], secreto: SECRETO });
    return { recibidas, hallazgos: Object.fromEntries(resultados.map((r) => [r.id, r.hallazgos])) };
  } finally {
    servidor.close();
  }
}

test('un servicio que cumple el contrato no tiene hallazgos', async () => {
  const { hallazgos, recibidas } = await verificarServicio();
  assert.deepEqual(hallazgos, { 'GET /salud': [], 'POST /nodos/{id}': [], 'POST /fotos': [], 'GET /texto': [] });
  assert.ok(recibidas.includes('POST /nodos/10000000-0000-4000-8000-000000000001?modo=RAPIDO'));
});

test('detecta una ruta que el servicio no tiene', async () => {
  const { hallazgos } = await verificarServicio({ 'POST /nodos': undefined, 'GET /texto': () => json(405, {}) });
  assert.deepEqual(hallazgos['POST /nodos/{id}'], ['la ruta no existe en el servicio']);
  assert.deepEqual(hallazgos['GET /texto'], ['la ruta no existe en el servicio']);
});

test('detecta una operación protegida que responde sin sesión', async () => {
  const { hallazgos } = await verificarServicio({
    'POST /nodos': () => json(201, { nombre: 'x' }),
    'POST /fotos': () => ({ estado: 204, tipo: '', cuerpo: '' }),
  });
  assert.deepEqual(hallazgos['POST /nodos/{id}'], ['sin sesión responde 201 en vez de 401']);
  assert.deepEqual(hallazgos['POST /fotos'], ['sin sesión responde 204 en vez de 401']);
});

test('detecta un código de respuesta que el contrato no documenta', async () => {
  const { hallazgos } = await verificarServicio({ 'GET /salud': () => json(503, { estado: 'caido' }) });
  assert.ok(hallazgos['GET /salud'].includes('[sin sesión] responde 503, que el contrato no documenta'));
});

test('detecta un cuerpo que no cumple el esquema, también el recursivo', async () => {
  const { hallazgos } = await verificarServicio({
    'GET /salud': () => json(200, {}),
    'POST /nodos': ({ sesion }) => (sesion ? json(201, { nombre: 'x', hijos: [{}] }) : json(401, { code: 'OTRO' })),
  });
  assert.match(hallazgos['GET /salud'][0], /cuerpo del 200: \/ must have required property 'estado'/);
  assert.match(hallazgos['POST /nodos/{id}'].join('\n'), /\/code must be equal to one of the allowed values \("OTRO"\)/);
  assert.match(hallazgos['POST /nodos/{id}'].join('\n'), /\/hijos\/0 must have required property 'nombre'/);
});

test('detecta un tipo de contenido que el contrato no documenta', async () => {
  const { hallazgos } = await verificarServicio({ 'GET /salud': () => ({ estado: 200, tipo: 'text/html', cuerpo: '<p>' }) });
  assert.match(hallazgos['GET /salud'][0], /content-type "text\/html" en vez de application\/json/);
});

test('firma un JWT HS256 con los claims de Core y Dispatch', () => {
  const [, contenido] = firmarToken({ secreto: SECRETO, rol: 'aliado', ahora: 100 }).split('.');
  const claims = JSON.parse(Buffer.from(contenido, 'base64url').toString());
  assert.equal(claims.app_metadata.user_role, 'aliado');
  assert.equal(claims.exp, 3700);
});

test('solo acepta un contrato conocido, un servicio local y el secreto de prueba', () => {
  const entorno = { SUPABASE_JWT_SECRET: SECRETO };
  const argumentos = (contrato, url) => ['--contrato', contrato, '--url', url];
  assert.equal(leerOpciones(argumentos('core', 'http://localhost:3000'), entorno).contrato, 'core');
  assert.throws(() => leerOpciones(argumentos('otro', 'http://localhost'), entorno), /--contrato/);
  assert.throws(() => leerOpciones(argumentos('core', 'https://api.mani.app'), entorno), /servicio local/);
  assert.throws(() => leerOpciones(['--contrato', 'core'], entorno), /servicio local/);
  assert.throws(() => leerOpciones(argumentos('core', 'http://localhost'), {}), /SUPABASE_JWT_SECRET/);
});

test('el informe falla con hallazgos o sin operaciones', () => {
  const con = informe([{ id: 'GET /a', hallazgos: [] }, { id: 'GET /b', hallazgos: ['x'] }]);
  assert.deepEqual(con, { lineas: ['✖ GET /b', '    x', '1 de 2 operaciones cumplen el contrato'], correcto: false });
  assert.equal(informe([]).correcto, false);
  assert.equal(informe([{ id: 'GET /a', hallazgos: [] }]).correcto, true);
});

test('principal informa el resultado y devuelve 1 si el servicio no cumple', async () => {
  const servidor = http.createServer((_req, res) => { res.writeHead(404); res.end(); });
  await new Promise((listo) => { servidor.listen(0, '127.0.0.1', listo); });
  const lineas = [];
  try {
    const url = `http://127.0.0.1:${servidor.address().port}`;
    const codigo = await principal(['--contrato', 'rules', '--url', url], { SUPABASE_JWT_SECRET: SECRETO }, (l) => lineas.push(l));
    assert.equal(codigo, 1);
    assert.equal(lineas.at(-1), '0 de 5 operaciones cumplen el contrato');
  } finally {
    servidor.close();
  }
});

test('la línea de comandos termina con error ante una opción inválida', () => {
  const { status, stderr } = spawnSync(process.execPath, [CLI, '--contrato', 'otro'], { encoding: 'utf8' });
  assert.equal(status, 1);
  assert.match(stderr, /--contrato debe ser uno de/);
});
