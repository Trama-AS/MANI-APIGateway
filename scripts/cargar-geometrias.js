#!/usr/bin/env node
/**
 * Genera el SQL que carga los límites de `supabase/seed/geometrias/` en la tabla
 * `geometria_territorial` (migración 0036 de MANI-Node, SCRUM-1396).
 *
 * Escribe en stdout y no abre ninguna conexión: así no añade `pg` a este
 * repositorio, cuyo package.json es solo herramienta de contrato (CFG-16), y
 * deja la ejecución —y las credenciales— en manos de quien aplica migraciones
 * en cada ambiente (README, «Quién ejecuta las migraciones en cada ambiente»).
 *
 *   node scripts/cargar-geometrias.js | psql "$DATABASE_URL"
 *
 * Las zonas se emparejan **por nombre**, no por identificador, porque los UUID
 * de `zona` los fija el seed de cada ambiente. Un nombre que no exista en
 * `zona` no se inventa: se reporta al final y su límite no se carga.
 *
 * Con `--crear-zonas` se dan de alta las localidades que falten, colgando de la
 * zona de nivel CIUDAD. Sin la bandera el script solo carga geometrías, que es
 * lo que corresponde en un ambiente cuyo catálogo ya administra alguien más.
 */
const fs = require('node:fs');
const path = require('node:path');

const DIR = path.join(__dirname, '..', 'supabase', 'seed', 'geometrias');

const FUENTE = 'Unidad Administrativa Especial de Catastro Distrital (UAECD)';
const LICENCIA = 'CC BY 4.0';
const ATRIBUCION = 'Límites: UAECD — Catastro Distrital de Bogotá (CC BY 4.0)';
// Fecha de actualización del dato en la fuente, no la de la descarga.
const FUENTE_FECHA = '2025-11-30';

const CAPAS = [
  {
    archivo: 'localidades_catastro.geojson',
    nivel: 'LOCALIDAD',
    nombre: (p) => p.LOCNOMBRE,
    codigo: (p) => p.LOCCODIGO,
  },
  {
    archivo: 'barrios_catastro.geojson',
    nivel: 'BARRIO',
    nombre: (p) => p.SCANOMBRE,
    codigo: (p) => p.SCACODIGO,
  },
];

const crearZonas = process.argv.includes('--crear-zonas');

/** Comilla simple para literales de texto en SQL. */
function texto(valor) {
  return `'${String(valor).replace(/'/g, "''")}'`;
}

/**
 * Nombre normalizado para emparejar: mayúsculas y sin tildes.
 *
 * El catastro publica «USAQUEN» y «LOS MARTIRES»; el catálogo guarda «Usaquén»
 * y «Los Mártires». Comparando solo con upper() no emparejan y se cargaría un
 * límite de más —o, con --crear-zonas, una localidad duplicada—. La eñe no se
 * toca: ambas fuentes escriben «NARIÑO».
 */
function nombreNormalizado(expresion) {
  return `upper(translate(${expresion}, 'ÁÉÍÓÚÜÀÈÌÒÙáéíóúüàèìòù', 'AEIOUUAEIOUaeiouuaeiou'))`;
}

const ZONA_NORM = nombreNormalizado('z.nombre');
const CARGA_NORM = nombreNormalizado('c.nombre');

/**
 * Comillas de dólar para el GeoJSON: son megabytes de JSON y escapar comillas
 * una por una sería costoso y frágil. Se elige una etiqueta que no aparezca en
 * el contenido para que no pueda cerrarse antes de tiempo.
 */
function jsonLiteral(valor) {
  const texto = JSON.stringify(valor);
  let etiqueta = 'geo';
  while (texto.includes(`$${etiqueta}$`)) etiqueta += 'x';
  return `$${etiqueta}$${texto}$${etiqueta}$`;
}

function leerCapa(capa) {
  const ruta = path.join(DIR, capa.archivo);
  const coleccion = JSON.parse(fs.readFileSync(ruta, 'utf8'));
  return (coleccion.features ?? []).map((f) => ({
    nivel: capa.nivel,
    nombre: capa.nombre(f.properties ?? {}),
    codigo: capa.codigo(f.properties ?? {}),
    geometria: f.geometry,
  }));
}

const salida = [];
const registros = CAPAS.flatMap(leerCapa);

salida.push('-- Generado por scripts/cargar-geometrias.js — no editar a mano.');
salida.push('-- Carga los límites de supabase/seed/geometrias/ en geometria_territorial (SCRUM-1396).');
salida.push('BEGIN;');
salida.push('');
salida.push('CREATE TEMP TABLE carga_geometria (');
salida.push('    nivel         TEXT NOT NULL,');
salida.push('    nombre        TEXT NOT NULL,');
salida.push('    codigo_fuente TEXT,');
salida.push('    geometria     JSONB NOT NULL');
salida.push(') ON COMMIT DROP;');
salida.push('');

for (const r of registros) {
  salida.push(
    `INSERT INTO carga_geometria (nivel, nombre, codigo_fuente, geometria) VALUES (${texto(r.nivel)}, ${texto(
      r.nombre
    )}, ${texto(r.codigo)}, ${jsonLiteral(r.geometria)}::jsonb);`
  );
}

salida.push('');
if (crearZonas) {
  salida.push('-- --crear-zonas: da de alta las localidades que falten bajo la zona CIUDAD.');
  salida.push('-- Solo LOCALIDAD: un barrio necesita saber de qué localidad cuelga, y eso');
  salida.push('-- no lo dice la capa catastral de sectores (ver README de la carpeta).');
  salida.push('-- initcap: el catastro publica en mayúsculas y sin tildes («ANTONIO NARIÑO»),');
  salida.push('-- y en un selector eso se lee mal junto a los nombres del seed. La forma');
  salida.push('-- canónica del nombre la fija el dueño del catálogo, no esta carga: las');
  salida.push('-- tildes que la fuente no trae («Ciudad Bolivar») hay que corregirlas allí.');
  salida.push('INSERT INTO zona (nivel, nombre, zona_padre_id, estado)');
  salida.push(
    "SELECT DISTINCT c.nivel, initcap(c.nombre), (SELECT id FROM zona WHERE nivel = 'CIUDAD' LIMIT 1), 'ACTIVO'"
  );
  salida.push('  FROM carga_geometria c');
  salida.push(" WHERE c.nivel = 'LOCALIDAD'");
  salida.push('   AND NOT EXISTS (');
  salida.push('       SELECT 1 FROM zona z');
  salida.push(`        WHERE z.nivel = c.nivel AND ${ZONA_NORM} = ${CARGA_NORM}`);
  salida.push('   );');
  salida.push('');
}

salida.push('-- Emparejamiento por nombre y nivel. ON CONFLICT (zona_id) porque la tabla');
salida.push('-- tiene UNIQUE en zona_id: recargar el seed actualiza el límite, no lo duplica.');
salida.push('INSERT INTO geometria_territorial');
salida.push('       (zona_id, geometria, fuente, codigo_fuente, licencia, atribucion, fuente_fecha)');
salida.push(
  `SELECT z.id, c.geometria, ${texto(FUENTE)}, c.codigo_fuente, ${texto(LICENCIA)}, ${texto(
    ATRIBUCION
  )}, DATE ${texto(FUENTE_FECHA)}`
);
salida.push('  FROM carga_geometria c');
salida.push(`  JOIN zona z ON z.nivel = c.nivel AND ${ZONA_NORM} = ${CARGA_NORM}`);
salida.push('    ON CONFLICT (zona_id) DO UPDATE');
salida.push('       SET geometria      = EXCLUDED.geometria,');
salida.push('           fuente         = EXCLUDED.fuente,');
salida.push('           codigo_fuente  = EXCLUDED.codigo_fuente,');
salida.push('           licencia       = EXCLUDED.licencia,');
salida.push('           atribucion     = EXCLUDED.atribucion,');
salida.push('           fuente_fecha   = EXCLUDED.fuente_fecha,');
salida.push('           actualizado_en = now();');
salida.push('');
salida.push('-- Lo que no se cargó, con nombre: un límite sin zona es un dato que falta en el');
salida.push('-- catálogo, no un error de este script. No se inventa la zona.');
salida.push('SELECT c.nivel, c.nombre AS sin_zona_en_el_catalogo');
salida.push('  FROM carga_geometria c');
salida.push(' WHERE NOT EXISTS (');
salida.push(`     SELECT 1 FROM zona z WHERE z.nivel = c.nivel AND ${ZONA_NORM} = ${CARGA_NORM}`);
salida.push(' )');
salida.push(' ORDER BY c.nivel, c.nombre;');
salida.push('');
salida.push('COMMIT;');
salida.push('');

process.stdout.write(salida.join('\n'));
