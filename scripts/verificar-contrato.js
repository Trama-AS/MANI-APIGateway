/**
 * Prueba de contrato de un servicio contra docs/openapi (QAS-23 / SCRUM-1724). La corren los CI de Core, Dispatch y
 * Rules con el servicio levantado en el job:
 *
 *   node scripts/verificar-contrato.js --contrato core --url http://localhost:3000/api/v1
 *
 * Por cada operación comprueba que la ruta exista, que sin sesión responda 401 si el contrato la exige, y que cada
 * respuesta tenga un código y un cuerpo documentados. El secreto con que se firman los JWT de prueba es
 * SUPABASE_JWT_SECRET, el mismo que recibe el servicio en el job. Nunca se apunta a un ambiente real: las sondas
 * envían peticiones de escritura.
 */
const path = require('node:path');
const { parseArgs } = require('node:util');
const { cargarContrato } = require('./contrato/operaciones');
const { verificarContrato } = require('./contrato/verificar');

const CONTRATOS = ['core', 'core-internal', 'dispatch', 'rules'];
const LOCALES = new Set(['localhost', '127.0.0.1', '[::1]']);
const ROLES = ['cliente', 'aliado', 'admin_tenant'];

function leerOpciones(argumentos, entorno) {
  const { values } = parseArgs({ args: argumentos, options: { contrato: { type: 'string' }, url: { type: 'string' } } });
  if (!CONTRATOS.includes(values.contrato)) throw new Error(`--contrato debe ser uno de: ${CONTRATOS.join(', ')}`);
  if (!values.url || !LOCALES.has(new URL(values.url).hostname)) throw new Error('--url debe apuntar a un servicio local');
  if (!entorno.SUPABASE_JWT_SECRET) throw new Error('Falta SUPABASE_JWT_SECRET (secreto de prueba)');
  return { contrato: values.contrato, url: values.url, secreto: entorno.SUPABASE_JWT_SECRET };
}

function informe(resultados) {
  const fallidas = resultados.filter((r) => r.hallazgos.length > 0);
  const lineas = fallidas.flatMap((r) => [`✖ ${r.id}`, ...r.hallazgos.map((h) => `    ${h}`)]);
  lineas.push(`${resultados.length - fallidas.length} de ${resultados.length} operaciones cumplen el contrato`);
  return { lineas, correcto: resultados.length > 0 && fallidas.length === 0 };
}

async function principal(argumentos, entorno, escribir) {
  const { contrato, url, secreto } = leerOpciones(argumentos, entorno);
  const cargado = await cargarContrato(path.join(__dirname, '..', 'docs', 'openapi', `${contrato}.yaml`));
  const { lineas, correcto } = informe(await verificarContrato({ ...cargado, base: url, roles: ROLES, secreto }));
  lineas.forEach((linea) => escribir(linea));
  return correcto ? 0 : 1;
}

module.exports = { informe, leerOpciones, principal };

if (require.main === module) {
  principal(process.argv.slice(2), process.env, console.log).then(
    (codigo) => { process.exitCode = codigo; },
    (err) => { console.error(`✖ ${err.message}`); process.exitCode = 1; }
  );
}
