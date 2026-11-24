const SwaggerParser = require('@apidevtools/swagger-parser');
const { muestra, UUID_MUESTRA } = require('./muestras');

const METODOS = ['get', 'post', 'put', 'patch', 'delete'];

/** Los parámetros de la operación reemplazan a los de la ruta con el mismo nombre y ubicación (OpenAPI 3.0). */
function parametrosDe(ruta, operacion) {
  const unicos = new Map();
  for (const parametro of [...(ruta.parameters || []), ...(operacion.parameters || [])]) {
    unicos.set(`${parametro.in}:${parametro.name}`, parametro);
  }
  return [...unicos.values()];
}

function listarOperaciones(api) {
  return Object.entries(api.paths).flatMap(([plantilla, ruta]) =>
    METODOS.filter((metodo) => ruta[metodo]).map((metodo) => {
      const operacion = ruta[metodo];
      return {
        id: `${metodo.toUpperCase()} ${plantilla}`,
        metodo: metodo.toUpperCase(),
        plantilla,
        parametros: parametrosDe(ruta, operacion),
        cuerpo: operacion.requestBody?.content?.['application/json']?.schema,
        soloArchivos: Boolean(operacion.requestBody) && !operacion.requestBody.content['application/json'],
        respuestas: operacion.responses,
        seguridad: operacion.security ?? api.security ?? [],
      };
    })
  );
}

/** Pública o con sesión opcional (`{}` entre las alternativas): no se le puede exigir 401. */
function exigeSesion(operacion) {
  return operacion.seguridad.length > 0 && operacion.seguridad.every((opcion) => Object.keys(opcion).length > 0);
}

function valorDeRuta(parametro) {
  const esquema = parametro.schema || {};
  if (esquema.format === 'uuid') return UUID_MUESTRA;
  return parametro.example ?? muestra(esquema);
}

function construirUrl(base, operacion) {
  const ruta = operacion.plantilla.replaceAll(/\{([^}]+)\}/g, (_, nombre) => {
    const parametro = operacion.parametros.find((p) => p.in === 'path' && p.name === nombre);
    return encodeURIComponent(String(parametro ? valorDeRuta(parametro) : UUID_MUESTRA));
  });
  const consulta = new URLSearchParams(
    operacion.parametros
      .filter((p) => p.in === 'query' && p.required)
      .map((p) => [p.name, String(p.example ?? muestra(p.schema))])
  ).toString();
  const url = base.replace(/\/$/, '') + ruta;
  return consulta ? `${url}?${consulta}` : url;
}

/** `contrato` conserva las referencias (para validar); `api` las resuelve (para armar las peticiones). */
async function cargarContrato(archivo) {
  return { contrato: await SwaggerParser.bundle(archivo), api: await SwaggerParser.dereference(archivo) };
}

module.exports = { cargarContrato, construirUrl, exigeSesion, listarOperaciones };
