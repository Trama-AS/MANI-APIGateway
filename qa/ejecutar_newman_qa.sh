#!/usr/bin/env bash
# Ejecuta la regresion Newman del Sprint 4 dentro de la VM de QA (SCRUM-1267 / SCRUM-1277).
#
# Por que en la VM: el Gateway de QA solo se alcanza de forma fiable desde la red del campus
# y el secreto JWT de QA vive en /opt/mani/.env.qa. Los tokens se firman aqui, no salen de la
# VM y se borran al terminar; el reporte se redacta antes de copiarlo.
#
# Uso (desde un equipo con la coleccion):
#   ssh estudiante@10.43.100.141 bash -s < qa/ejecutar_newman_qa.sh   (con COLECCION_B64 embebida)
# o en la VM:
#   COLECCION=/ruta/coleccion.json bash qa/ejecutar_newman_qa.sh
set -euo pipefail

main() {
  local marca dir env_qa
  if ! docker info >/dev/null 2>&1; then
    echo "ABORTA: Docker no esta disponible para el usuario $(id -un); Newman corre en contenedor" >&2
    return 1
  fi
  marca=$(date -u +%Y%m%dT%H%M%SZ)
  dir="${HOME}/scrum_1267/${marca}"
  env_qa="${ENV_QA:-/opt/mani/.env.qa}"
  mkdir -p "$dir"
  chmod 700 "$dir"

  if [ -n "${COLECCION_B64:-}" ]; then
    printf '%s' "$COLECCION_B64" | base64 -d > "$dir/coleccion.json"
  else
    cp "${COLECCION:?definir COLECCION o COLECCION_B64}" "$dir/coleccion.json"
  fi

  echo "== 1. Tokens HS256 de prueba (firmados con el secreto de QA, no se imprimen)"
  ENV_QA="$env_qa" SALIDA="$dir/entorno.json" BASE_URL="${BASE_URL:-http://localhost}" python3 - <<'PY'
import base64, hashlib, hmac, json, os, time

def leer_secreto(ruta):
    for linea in open(ruta, encoding='utf8'):
        if linea.startswith('SUPABASE_JWT_SECRET='):
            return linea.split('=', 1)[1].strip().strip("'\"")
    raise SystemExit('ABORTA: no hay SUPABASE_JWT_SECRET en el .env de QA')

def b64(datos):
    return base64.urlsafe_b64encode(datos).rstrip(b'=').decode()

def firmar(carga, clave):
    cabecera = b64(json.dumps({'alg': 'HS256', 'typ': 'JWT'}, separators=(',', ':')).encode())
    cuerpo = b64(json.dumps(carga, separators=(',', ':')).encode())
    firma = hmac.new(clave.encode(), f'{cabecera}.{cuerpo}'.encode(), hashlib.sha256).digest()
    return f'{cabecera}.{cuerpo}.{b64(firma)}'

secreto = leer_secreto(os.environ['ENV_QA'])
ahora = int(time.time())
t1, t2 = '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000021'
usuarios = {
    'admin_t1': ('30000000-0000-4000-8000-000000000011', t1, 'ADMIN_TENANT'),
    'cliente_t1': ('30000000-0000-4000-8000-000000000012', t1, 'CLIENTE'),
    'aliado_t1': ('30000000-0000-4000-8000-000000000013', t1, 'ALIADO'),
    'admin_t2': ('30000000-0000-4000-8000-000000000021', t2, 'ADMIN_TENANT'),
    'cliente_t2': ('30000000-0000-4000-8000-000000000022', t2, 'CLIENTE'),
    'aliado_t2': ('30000000-0000-4000-8000-000000000023', t2, 'ALIADO'),
    'aliado_t1b': ('ee52e2b9-3044-4e30-b0b9-cb744e677527', t1, 'ALIADO'),
    'aliado_poc1': ('30000000-0000-4000-8000-900000000001', '10000000-0000-4000-8000-900000000001', 'ALIADO'),
    'aliado_poc2': ('30000000-0000-4000-8000-900000000002', '10000000-0000-4000-8000-900000000001', 'ALIADO'),
}

def carga(sub, tenant, rol, exp):
    meta = {'user_role': rol}
    if tenant:
        meta['tenant_id'] = tenant
    return {'sub': sub, 'role': 'authenticated', 'aud': 'authenticated', 'iat': ahora, 'exp': exp, 'app_metadata': meta}

tokens = {f'token_{k}': firmar(carga(s, t, r, ahora + 3600), secreto) for k, (s, t, r) in usuarios.items()}
s, t, r = usuarios['cliente_t1']
tokens['token_expirado'] = firmar(carga(s, t, r, ahora - 60), secreto)
tokens['token_alterado'] = firmar(carga(s, t, r, ahora + 3600), secreto + 'x')
tokens['token_sin_tenant'] = firmar(carga(s, None, r, ahora + 3600), secreto)

entorno = {'name': 'qa', 'values': [{'key': 'base_url', 'value': os.environ.get('BASE_URL', 'http://localhost'), 'enabled': True}] +
           [{'key': k, 'value': v, 'enabled': True} for k, v in tokens.items()]}
salida = os.environ['SALIDA']
with open(salida, 'w', encoding='utf8') as f:
    json.dump(entorno, f)
os.chmod(salida, 0o600)
print(f'OK: {len(tokens)} tokens de prueba listos (expiran en 1 h)')
PY

  echo "== 2. Newman contra el Gateway de QA (${BASE_URL:-http://localhost})"
  set +e
  docker run --rm --network host -v "$dir":/etc/newman postman/newman:6-alpine run coleccion.json \
    -e entorno.json --reporters cli,json --reporter-json-export resultado_crudo.json --color off --disable-unicode
  local codigo=$?
  set -e
  echo "Codigo de salida de Newman: ${codigo}"

  echo "== 3. Redaccion del reporte y borrado de tokens"
  DIR="$dir" python3 - <<'PY'
import json, os, re, sys
d = os.environ['DIR']
tokens = [v['value'] for v in json.load(open(f'{d}/entorno.json'))['values'] if v['key'].startswith('token_')]
texto = open(f'{d}/resultado_crudo.json', encoding='utf8').read()
for t in tokens:
    texto = texto.replace(t, '<token_redactado>')
reporte = json.loads(texto)
for clave in ('environment', 'globals'):
    reporte.get('run', {}).pop(clave, None)
    reporte.pop(clave, None)

JWT = re.compile(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}')
SENSIBLES = re.compile(r'("(?:temporaryPassword|accessToken|refreshToken|access_token|refresh_token|password|token|apikey|secret)"\s*:\s*")([^"]*)(")', re.I)

def limpiar(s):
    return JWT.sub('<jwt_redactado>', SENSIBLES.sub(r'\1<redactado>\3', s))

def cuerpo_de(resp):
    flujo = resp.get('stream')
    if isinstance(flujo, dict) and flujo.get('data') is not None:
        return bytes(flujo['data']).decode('utf8', 'replace')
    return ''

# Newman guarda las respuestas como arreglos de bytes: se decodifican, se enmascaran las
# credenciales y se guarda solo el texto limpio (nunca los bytes originales).
for ex in reporte['run']['executions']:
    resp = ex.setdefault('response', {})
    resp['body_texto'] = limpiar(cuerpo_de(resp))[:4000]
    resp.pop('stream', None)
    for peticion in (ex.get('request') or {}, (ex.get('item') or {}).get('request') or {}):
        cuerpo = peticion.get('body')
        if isinstance(cuerpo, dict) and isinstance(cuerpo.get('raw'), str):
            cuerpo['raw'] = limpiar(cuerpo['raw'])
        for h in peticion.get('header') or []:
            if isinstance(h, dict) and str(h.get('key', '')).lower() == 'authorization':
                h['value'] = 'Bearer <token_redactado>'

def cadenas(o):
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for v in o.values():
            yield from cadenas(v)
    elif isinstance(o, list):
        for v in o:
            yield from cadenas(v)

malas = [s[:40] for s in cadenas(reporte)
         if JWT.search(s) or re.search(r'"(?:temporaryPassword|accessToken|refreshToken)"\s*:\s*"(?!<redactado>)', s)]
if malas:
    for f in ('resultado_crudo.json', 'entorno.json'):
        if os.path.exists(f'{d}/{f}'):
            os.remove(f'{d}/{f}')
    sys.exit('ABORTA: el reporte aun contiene credenciales; no se guarda evidencia')
open(f'{d}/resultado_redactado.json', 'w', encoding='utf8').write(json.dumps(reporte))

# Resumen por caso para la matriz.
filas = []
for ex in reporte['run']['executions']:
    nombre = ex['item']['name']
    codigo = ex.get('response', {}).get('code')
    fallas = [a['assertion'] for a in ex.get('assertions', []) if a.get('error')]
    cuerpo = ex.get('response', {}).get('body_texto', '')[:180].replace('\n', ' ')
    filas.append({'caso': nombre, 'http': codigo, 'resultado': 'FALLA' if fallas else 'OK', 'fallas': fallas, 'cuerpo': cuerpo})
json.dump(filas, open(f'{d}/resumen.json', 'w', encoding='utf8'), ensure_ascii=False, indent=1)
st = reporte['run']['stats']
print(f"Solicitudes {st['requests']['total']} | aserciones {st['assertions']['total']} | fallidas {st['assertions']['failed']}")
print('Redaccion verificada: sin JWT ni contrasenas temporales en el reporte')
for f in filas:
    print(f"{f['resultado']:5} {f['http']} {f['caso']}" + (f"  <- {f['cuerpo']}" if f['resultado'] == 'FALLA' else ''))
PY
  rm -f "$dir/entorno.json" "$dir/resultado_crudo.json"
  echo "Evidencia redactada en ${dir} (resultado_redactado.json, resumen.json)"
  echo "DIRECTORIO_EVIDENCIA=${dir}"
  # En CI el codigo de Newman es el gate; en los lotes manuales se sigue con el resto.
  if [ "${SALIR_CON_CODIGO:-0}" = "1" ]; then return "$codigo"; fi
}

main < /dev/null
