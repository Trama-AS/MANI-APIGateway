#!/usr/bin/env bash
# Ejecuta la suite Playwright del Sprint 4 dentro de la VM de QA (SCRUM-1267 / SCRUM-1278).
#
# La suite llega empaquetada en SUITE_B64 (tar.gz de qa/playwright) o en SUITE_DIR. Los tokens
# de prueba se firman aqui con el secreto de /opt/mani/.env.qa, viven 15 minutos y se pasan al
# contenedor por un env-file que se borra al terminar. Los traces (que incluyen esos tokens ya
# vencidos) se quedan en la VM; solo se imprime el resumen.
set -euo pipefail

main() {
  local marca dir env_qa imagen
  if ! docker info >/dev/null 2>&1; then
    echo "ABORTA: Docker no esta disponible para el usuario $(id -un); Playwright corre en contenedor" >&2
    return 1
  fi
  marca=$(date -u +%Y%m%dT%H%M%SZ)
  dir="${HOME}/scrum_1267/playwright_${marca}"
  env_qa="${ENV_QA:-/opt/mani/.env.qa}"
  imagen='mcr.microsoft.com/playwright:v1.48.2-jammy'
  mkdir -p "$dir"; chmod 700 "$dir"
  if [ -n "${SUITE_B64:-}" ]; then
    printf '%s' "$SUITE_B64" | base64 -d | tar xzf - -C "$dir"
  else
    cp -r "${SUITE_DIR:?definir SUITE_DIR o SUITE_B64}/." "$dir/"
  fi

  echo "== 1. Tokens de prueba (15 min, no se imprimen)"
  ENV_QA="$env_qa" SALIDA="$dir/tokens.env" python3 - <<'PY'
import base64, hashlib, hmac, json, os, time
secreto = next(l.split('=', 1)[1].strip().strip("'\"") for l in open(os.environ['ENV_QA'], encoding='utf8') if l.startswith('SUPABASE_JWT_SECRET='))
b64 = lambda d: base64.urlsafe_b64encode(d).rstrip(b'=').decode()
def firmar(carga):
    c = b64(json.dumps({'alg': 'HS256', 'typ': 'JWT'}, separators=(',', ':')).encode())
    p = b64(json.dumps(carga, separators=(',', ':')).encode())
    return f"{c}.{p}.{b64(hmac.new(secreto.encode(), f'{c}.{p}'.encode(), hashlib.sha256).digest())}"
ahora = int(time.time())
t1, t2 = '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000021'
usuarios = {
    'ADMIN_T1': ('30000000-0000-4000-8000-000000000011', t1, 'ADMIN_TENANT'),
    'CLIENTE_T1': ('30000000-0000-4000-8000-000000000012', t1, 'CLIENTE'),
    'ALIADO_T1': ('30000000-0000-4000-8000-000000000013', t1, 'ALIADO'),
    'ALIADO_T2': ('30000000-0000-4000-8000-000000000023', t2, 'ALIADO'),
}
with open(os.environ['SALIDA'], 'w', encoding='utf8') as f:
    for k, (s, t, r) in usuarios.items():
        tok = firmar({'sub': s, 'role': 'authenticated', 'aud': 'authenticated', 'iat': ahora, 'exp': ahora + 900,
                      'app_metadata': {'tenant_id': t, 'user_role': r}})
        f.write(f'TOKEN_{k}={tok}\n')
os.chmod(os.environ['SALIDA'], 0o600)
print(f'OK: {len(usuarios)} tokens')
PY

  # En la VM de QA las URLs son localhost; desde el runner de Calidad llegan por el entorno (workflow qa-regresion.yml).
  local url_gateway="${URL_GATEWAY:-http://localhost}"
  local url_flutter="${URL_FLUTTER:-http://localhost:8080}"
  local url_landing="${URL_LANDING:-http://localhost:3001}"
  echo "== 2. Playwright (${imagen}) contra ${url_gateway}"
  set +e
  docker run --rm --network host --ipc=host --env-file "$dir/tokens.env" \
    -e URL_GATEWAY="$url_gateway" -e URL_FLUTTER="$url_flutter" -e URL_LANDING="$url_landing" \
    -v "$dir":/suite -w /suite "$imagen" \
    bash -c 'npm ci --no-audit --no-fund --silent >/dev/null 2>&1 && npx playwright test'
  local codigo=$?
  set -e
  rm -f "$dir/tokens.env"
  echo "Codigo de salida de Playwright: ${codigo}"

  echo "== 3. Resumen"
  DIR="$dir" python3 - <<'PY'
import json, os
d = os.environ['DIR']
r = json.load(open(f'{d}/resultados.json', encoding='utf8'))
def recorrer(suite, prefijo=''):
    for s in suite.get('suites', []):
        yield from recorrer(s, prefijo + s.get('title', '') + ' > ')
    for spec in suite.get('specs', []):
        for t in spec.get('tests', []):
            res = t.get('results', [{}])[-1]
            notas = '; '.join(f"{a.get('type')}: {a.get('description')}" for a in t.get('annotations', []))
            error = (res.get('error') or {}).get('message', '').split('\n')[0][:200]
            yield res.get('status'), spec['title'], notas, error
for estado, titulo, notas, error in recorrer(r):
    print(f'{estado:8} {titulo}' + (f'  | {notas}' if notas else '') + (f'  | {error}' if error and estado != 'passed' else ''))
s = r.get('stats', {})
print(f"Totales: esperados={s.get('expected')} fallidos={s.get('unexpected')} omitidos={s.get('skipped')}")
PY
  echo "DIRECTORIO_EVIDENCIA=${dir}"
  # En CI el codigo de Playwright es el gate; en los lotes manuales se sigue con el resto.
  if [ "${SALIR_CON_CODIGO:-0}" = "1" ]; then return "$codigo"; fi
}

main < /dev/null
