/**
 * Valores de muestra a partir de un esquema OpenAPI 3.0 ya desreferenciado. Son deterministas: la misma entrada da
 * siempre la misma petición, para que un fallo del CI se pueda repetir en local.
 */
const UUID_MUESTRA = '10000000-0000-4000-8000-000000000001';
const PROFUNDIDAD_MAXIMA = 8;

const POR_FORMATO = {
  uuid: UUID_MUESTRA,
  date: '2026-01-15',
  'date-time': '2026-01-15T10:00:00.000Z',
  email: 'contrato@example.com',
  uri: 'https://example.com/contrato',
};

function texto(esquema) {
  if (POR_FORMATO[esquema.format]) return POR_FORMATO[esquema.format];
  const minimo = esquema.minLength || 0;
  return 'contrato'.padEnd(minimo, 'x').slice(0, esquema.maxLength || undefined);
}

function numero(esquema) {
  return Math.min(Math.max(esquema.minimum ?? 1, 0), esquema.maximum ?? Infinity);
}

function combinar(partes, profundidad) {
  return partes.reduce((suma, parte) => {
    const valor = muestra(parte, profundidad);
    return valor && typeof valor === 'object' ? { ...suma, ...valor } : suma;
  }, {});
}

function objeto(esquema, profundidad) {
  const propiedades = esquema.properties || {};
  return Object.fromEntries(
    (esquema.required || [])
      .filter((nombre) => propiedades[nombre] && !propiedades[nombre].readOnly)
      .map((nombre) => [nombre, muestra(propiedades[nombre], profundidad + 1)])
  );
}

function porTipo(esquema, profundidad) {
  switch (esquema.type) {
    case 'string': return texto(esquema);
    case 'integer':
    case 'number': return numero(esquema);
    case 'boolean': return true;
    case 'array': return Array.from({ length: esquema.minItems || 0 }, () => muestra(esquema.items || {}, profundidad + 1));
    default: return objeto(esquema, profundidad);
  }
}

function muestra(esquema = {}, profundidad = 0) {
  if (profundidad > PROFUNDIDAD_MAXIMA) return null;
  if (esquema.example !== undefined) return esquema.example;
  if (esquema.default !== undefined) return esquema.default;
  if (esquema.enum) return esquema.enum[0];
  if (esquema.allOf) return { ...combinar(esquema.allOf, profundidad), ...objeto(esquema, profundidad) };
  const alternativa = esquema.oneOf?.[0] || esquema.anyOf?.[0];
  return alternativa ? muestra(alternativa, profundidad) : porTipo(esquema, profundidad);
}

module.exports = { muestra, UUID_MUESTRA };
