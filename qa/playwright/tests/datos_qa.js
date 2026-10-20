// Datos y URLs compartidos por las pruebas E2E. Los tokens llegan por variables de entorno
// (TOKEN_ADMIN_T1, TOKEN_CLIENTE_T1, ...) firmadas en la VM de QA por qa/ejecutar_playwright_qa.sh.
const url_gateway = process.env.URL_GATEWAY || 'http://localhost';
const url_flutter = process.env.URL_FLUTTER || 'http://localhost:8080';
const url_landing = process.env.URL_LANDING || 'http://localhost:3001';

const datos = {
  ref_supabase_qa: 'hpsxdotaizzclkeufzct',
  categoria_t1: '60000000-0000-4000-8000-000000000011',
  sitio_t1: '70000000-0000-4000-8000-000000000011',
  zona_cobertura: '20000000-0000-4000-8000-000000000002',
  aliado_t1: '50000000-0000-4000-8000-000000000011',
  aliado_t2: '50000000-0000-4000-8000-000000000021',
};

function token(nombre) {
  const valor = process.env[`TOKEN_${nombre.toUpperCase()}`];
  if (!valor) throw new Error(`Falta TOKEN_${nombre.toUpperCase()} en el entorno`);
  return valor;
}

function cabeceras(nombre) {
  return { Authorization: `Bearer ${token(nombre)}`, 'Content-Type': 'application/json' };
}

module.exports = { url_gateway, url_flutter, url_landing, datos, cabeceras };
