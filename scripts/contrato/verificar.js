const crypto = require('node:crypto');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const { construirUrl, exigeSesion, listarOperaciones } = require('./operaciones');
const { muestra, UUID_MUESTRA } = require('./muestras');

const CAMPOS_VARIABLES = ['correlationId', 'timestamp', 'path', 'traceId'];
const ID_CONTRATO = 'https://mani.local/contrato';
const TIEMPO_MAXIMO_MS = 15_000;
const TIPO_JSON = 'application/json';

function describirError({ keyword, instancePath, message, data }) {
  const valor = keyword === 'enum' ? ` (${JSON.stringify(data)})` : '';
  return `${instancePath || '/'} ${message}${valor}`;
}

/**
 * Valida cuerpos con los esquemas del contrato sin desreferenciar: así los esquemas recursivos (geometrías, árboles) se
 * resuelven por referencia y no se expanden sin fin.
 */
function crearValidador(contrato) {
  const ajv = new Ajv({ strict: false, allErrors: true, verbose: true });
  addFormats(ajv);
  ajv.addSchema({ ...contrato, $id: ID_CONTRATO }, ID_CONTRATO);
  return (puntero, dato) => {
    const validar = ajv.getSchema(`${ID_CONTRATO}${puntero}`);
    return validar(dato) ? [] : validar.errors.map(describirError);
  };
}

function segmento(clave) {
  return encodeURIComponent(clave.replaceAll('~', '~0').replaceAll('/', '~1'));
}

/** Puntero JSON del esquema de una respuesta; las respuestas compartidas apuntan a components/responses. */
function punteroDeEsquema(contrato, operacion, clave) {
  const respuesta = contrato.paths[operacion.plantilla][operacion.metodo.toLowerCase()].responses[clave];
  const base = respuesta.$ref
    || `#/paths/${segmento(operacion.plantilla)}/${operacion.metodo.toLowerCase()}/responses/${clave}`;
  return `${base}/content/${segmento(TIPO_JSON)}/schema`;
}

/** JWT HS256 con los claims que exigen Core y Dispatch (ADR-0031 §2). Solo sirve con el secreto de prueba del CI. */
function firmarToken({ secreto, rol, ahora = Math.floor(Date.now() / 1000) }) {
  const parte = (dato) => Buffer.from(JSON.stringify(dato)).toString('base64url');
  const contenido = `${parte({ alg: 'HS256', typ: 'JWT' })}.${parte({
    sub: UUID_MUESTRA,
    aud: 'authenticated',
    iat: ahora,
    exp: ahora + 3600,
    app_metadata: { tenant_id: UUID_MUESTRA, user_role: rol },
  })}`;
  return `${contenido}.${crypto.createHmac('sha256', secreto).update(contenido).digest('base64url')}`;
}

function encabezadosDeSesion(rol, secreto) {
  // Rules no lee el JWT: recibe el tenant y el rol de quien ya lo validó (Gateway o Core).
  return { Authorization: `Bearer ${firmarToken({ secreto, rol })}`, 'X-Tenant-Id': UUID_MUESTRA, 'X-User-Role': rol };
}

async function enviar({ url, metodo, encabezados = {}, cuerpo }) {
  const conCuerpo = cuerpo !== undefined && metodo !== 'GET';
  const respuesta = await fetch(url, {
    method: metodo,
    redirect: 'manual',
    signal: AbortSignal.timeout(TIEMPO_MAXIMO_MS),
    headers: { ...encabezados, ...(conCuerpo && { 'Content-Type': 'application/json' }) },
    body: conCuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  return { estado: respuesta.status, tipo: respuesta.headers.get('content-type') || '', texto: await respuesta.text() };
}

/** Huella de una respuesta sin los campos que cambian en cada petición. */
function huella({ estado, texto }) {
  let contenido = texto;
  try {
    const json = JSON.parse(texto);
    if (json && typeof json === 'object') {
      contenido = JSON.stringify(Object.fromEntries(Object.entries(json).filter(([campo]) => !CAMPOS_VARIABLES.includes(campo))));
    }
  } catch {
    // Cuerpo vacío o que no es JSON: se compara tal cual.
  }
  return `${estado}:${contenido}`;
}

function claveDocumentada(respuestas, estado) {
  return [String(estado), `${Math.floor(estado / 100)}XX`, 'default'].find((clave) => respuestas[clave]);
}

function revisarCuerpo({ contrato, operacion, clave, respuesta, validar }) {
  const contenido = operacion.respuestas[clave].content || {};
  if (!contenido[TIPO_JSON]?.schema) return [];
  if (!respuesta.tipo.includes('json')) {
    const otroTipo = Object.keys(contenido).some((tipo) => tipo !== TIPO_JSON && respuesta.tipo.includes(tipo));
    return otroTipo ? [] : [`content-type "${respuesta.tipo}" en vez de ${TIPO_JSON}`];
  }
  return validar(punteroDeEsquema(contrato, operacion, clave), JSON.parse(respuesta.texto));
}

function revisarRespuesta({ contrato, operacion, respuesta, validar }) {
  const clave = claveDocumentada(operacion.respuestas, respuesta.estado);
  if (!clave) return [`responde ${respuesta.estado}, que el contrato no documenta`];
  return revisarCuerpo({ contrato, operacion, clave, respuesta, validar })
    .map((error) => `cuerpo del ${respuesta.estado}: ${error}`);
}

/** Sin sesión, con sesión y cuerpo vacío, y con sesión y un cuerpo que cumple el contrato. */
function sondasDe(operacion, roles, secreto) {
  const cuerpoDeMuestra = operacion.cuerpo ? muestra(operacion.cuerpo) : {};
  const sondas = [{ nombre: 'sin sesión', sinSesion: true, encabezados: {}, cuerpo: cuerpoDeMuestra }];
  for (const rol of roles) {
    const encabezados = encabezadosDeSesion(rol, secreto);
    sondas.push({ nombre: `${rol}, cuerpo vacío`, encabezados, cuerpo: {} });
    if (operacion.cuerpo) sondas.push({ nombre: `${rol}, cuerpo de muestra`, encabezados, cuerpo: cuerpoDeMuestra });
  }
  return sondas;
}

/** Las cargas de archivo leen el multipart antes que el token: sin archivo, el rechazo puede ser un 400. */
function rechazaSinSesion(operacion, estado) {
  if (!exigeSesion(operacion)) return true;
  return estado === 401 || (operacion.soloArchivos && estado === 400);
}

async function verificarOperacion({ contrato, base, operacion, roles, secreto, huellaInexistente, validar }) {
  const url = construirUrl(base, operacion);
  const hallazgos = new Set();
  for (const sonda of sondasDe(operacion, roles, secreto)) {
    const respuesta = await enviar({ url, metodo: operacion.metodo, encabezados: sonda.encabezados, cuerpo: sonda.cuerpo });
    if (respuesta.estado === 405 || huella(respuesta) === huellaInexistente) return ['la ruta no existe en el servicio'];
    if (sonda.sinSesion && !rechazaSinSesion(operacion, respuesta.estado)) {
      hallazgos.add(`sin sesión responde ${respuesta.estado} en vez de 401`);
    }
    for (const error of revisarRespuesta({ contrato, operacion, respuesta, validar })) hallazgos.add(`[${sonda.nombre}] ${error}`);
  }
  return [...hallazgos];
}

/** Compara el servicio que responde en `base` con el contrato. Devuelve una entrada por operación. */
async function verificarContrato({ contrato, api, base, roles, secreto }) {
  const validar = crearValidador(contrato);
  const inexistente = await enviar({
    url: `${base.replace(/\/$/, '')}/ruta-inexistente-contrato`,
    metodo: 'GET',
    encabezados: encabezadosDeSesion(roles[0], secreto),
  });
  const resultados = [];
  for (const operacion of listarOperaciones(api)) {
    const hallazgos = await verificarOperacion({
      contrato, base, operacion, roles, secreto, validar, huellaInexistente: huella(inexistente),
    });
    resultados.push({ id: operacion.id, hallazgos });
  }
  return resultados;
}

module.exports = { firmarToken, huella, revisarRespuesta, verificarContrato };
