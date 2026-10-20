/**
 * Genera postman/MANI-Rules.postman_collection.json: suite de contrato de
 * POST /api/v1/rules/categories/evaluate (docs/openapi/rules.yaml) que corre
 * contra el Gateway REAL (auth_request a Core + reenvío a MANI-Java), con
 * escenarios válidos, inválidos, inactivos, de autorización y de tenant
 * (US-03.1.1-M6 / SCRUM-1226).
 *
 * Los JWT se firman en el sandbox de Postman (CryptoJS, HS256) con
 * {{jwtSecret}}, el mismo SUPABASE_JWT_SECRET que usa Core en el entorno.
 */
const fs = require('node:fs');
const path = require('node:path');

const OUTPUT_PATH = path.join(__dirname, '..', 'postman', 'MANI-Rules.postman_collection.json');
const EVALUATE = '/api/v1/rules/categories/evaluate';

const ERROR_SCHEMA = {
  type: 'object',
  required: ['error', 'code', 'correlationId'],
  properties: { error: { type: 'string' }, code: { type: 'string' }, correlationId: { type: 'string' } },
};

const EVALUATION_SCHEMA = {
  type: 'object',
  required: ['allowed', 'ruleSetVersion', 'violations', 'normalized', 'tenantId', 'operation', 'correlationId'],
  properties: {
    allowed: { type: 'boolean' },
    ruleSetVersion: { type: 'string' },
    violations: {
      type: 'array',
      items: {
        type: 'object',
        required: ['code', 'field', 'message'],
        properties: {
          code: { type: 'string', enum: ['MANI-CAT-422N', 'MANI-CAT-422F', 'MANI-CAT-422C'] },
          field: { type: 'string' },
          message: { type: 'string' },
        },
      },
    },
    normalized: { type: 'object' },
    tenantId: { type: 'string' },
    operation: { type: 'string', enum: ['CREATE', 'UPDATE', 'OPERATE'] },
    correlationId: { type: 'string' },
  },
};

// Firma HS256 en el sandbox de Postman y deja un token por perfil en variables.
const SIGN_TOKENS = [
  "const cryptoJs = require('crypto-js');",
  'function b64url(wordArrayOrString) {',
  "  const wa = typeof wordArrayOrString === 'string' ? cryptoJs.enc.Utf8.parse(wordArrayOrString) : wordArrayOrString;",
  "  return cryptoJs.enc.Base64.stringify(wa).replace(/=+$/, '').replace(/\\+/g, '-').replace(/\\//g, '_');",
  '}',
  'function signJwt(sub, tenantId, role) {',
  '  const now = Math.floor(Date.now() / 1000);',
  "  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));",
  '  const payload = b64url(JSON.stringify({ sub, iat: now, exp: now + 3600, app_metadata: { tenant_id: tenantId, user_role: role } }));',
  "  const signature = b64url(cryptoJs.HmacSHA256(header + '.' + payload, pm.variables.get('jwtSecret')));",
  "  return header + '.' + payload + '.' + signature;",
  '}',
  "pm.variables.set('adminTokenA', signJwt('qa-admin-a', pm.variables.get('tenantA'), 'admin_tenant'));",
  "pm.variables.set('allyTokenA', signJwt('qa-ally-a', pm.variables.get('tenantA'), 'aliado'));",
  "pm.variables.set('correlationId', 'newman-rules-' + Date.now() + '-' + Math.floor(Math.random() * 1e6));",
];

function test(lines) {
  return [{ listen: 'test', script: { type: 'text/javascript', exec: lines } }];
}

function expectStatus(code) {
  return `pm.test('status ${code}', () => pm.response.to.have.status(${code}));`;
}

const SCHEMA_HELPER = [
  "const Ajv = require('ajv');",
  'let schemaErrors = null;',
  'function validateSchema(schema, data) {',
  '  const ajv = new Ajv({ allErrors: true });',
  '  const ok = ajv.validate(schema, data);',
  '  schemaErrors = ajv.errors;',
  '  return ok;',
  '}',
];

function evaluationAsserts() {
  return [
    ...SCHEMA_HELPER,
    expectStatus(200),
    `const body = pm.response.json();`,
    `pm.test('cumple el esquema CategoryEvaluationResponse', () => pm.expect(validateSchema(${JSON.stringify(EVALUATION_SCHEMA)}, body), JSON.stringify(schemaErrors)).to.be.true);`,
    "pm.test('tenant = claim del JWT (tenantA)', () => pm.expect(body.tenantId).to.eql(pm.variables.get('tenantA')));",
    "pm.test('propaga X-Correlation-ID', () => { pm.expect(body.correlationId).to.eql(pm.variables.get('correlationId')); pm.expect(pm.response.headers.get('X-Correlation-ID')).to.include(pm.variables.get('correlationId')); });",
  ];
}

function errorAsserts(status, code) {
  return [
    ...SCHEMA_HELPER,
    expectStatus(status),
    'const body = pm.response.json();',
    `pm.test('cumple el esquema ApiError', () => pm.expect(validateSchema(${JSON.stringify(ERROR_SCHEMA)}, body), JSON.stringify(schemaErrors)).to.be.true);`,
    `pm.test('code ${code}', () => pm.expect(body.code).to.eql('${code}'));`,
  ];
}

function evaluateRequest(name, { token = '{{adminTokenA}}', body, extraHeaders = [], asserts }) {
  const header = [
    { key: 'Content-Type', value: 'application/json' },
    { key: 'X-Correlation-ID', value: '{{correlationId}}' },
    ...(token ? [{ key: 'Authorization', value: `Bearer ${token}` }] : []),
    ...extraHeaders,
  ];
  return {
    name,
    event: test(asserts),
    request: {
      method: 'POST',
      header,
      body: { mode: 'raw', raw: JSON.stringify(body, null, 2), options: { raw: { language: 'json' } } },
      url: { raw: `{{baseUrl}}${EVALUATE}`, host: ['{{baseUrl}}'], path: EVALUATE.slice(1).split('/') },
    },
  };
}

const items = [
  {
    name: 'Health de Rules a través del Gateway',
    event: test([expectStatus(200), "pm.test('UP', () => pm.expect(pm.response.json().status).to.eql('UP'));"]),
    request: {
      method: 'GET',
      header: [{ key: 'X-Correlation-ID', value: '{{correlationId}}' }],
      url: { raw: '{{baseUrl}}/api/v1/rules/health', host: ['{{baseUrl}}'], path: ['api', 'v1', 'rules', 'health'] },
    },
  },
  evaluateRequest('CREATE válida: aprueba y normaliza nombre y flujo', {
    body: { categoryId: null, context: { operation: 'CREATE', name: '  Plomería   Express ', flujoOperativo: 'tarifa_estandar' } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('allowed=true sin violaciones', () => { pm.expect(body.allowed).to.be.true; pm.expect(body.violations).to.be.empty; });",
      "pm.test('normaliza', () => pm.expect(body.normalized).to.eql({ name: 'Plomería Express', flujoOperativo: 'TARIFA_ESTANDAR' }));",
      "pm.test('ruleSetVersion presente', () => pm.expect(body.ruleSetVersion).to.match(/^category-rules/));",
    ],
  }),
  evaluateRequest('CREATE límite inferior: 3 caracteres es válido', {
    body: { context: { operation: 'CREATE', name: 'Abc', flujoOperativo: 'COTIZACION_PREVIA' } },
    asserts: [...evaluationAsserts(), "pm.test('3 caracteres aprueba', () => pm.expect(body.allowed).to.be.true);"],
  }),
  evaluateRequest('CREATE límite superior: 60 caracteres es válido', {
    body: { context: { operation: 'CREATE', name: 'A'.repeat(60), flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: [...evaluationAsserts(), "pm.test('60 caracteres aprueba', () => pm.expect(body.allowed).to.be.true);"],
  }),
  evaluateRequest('CREATE inválida: nombre de 2 caracteres sin letras (MANI-CAT-422N)', {
    body: { context: { operation: 'CREATE', name: '12', flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('allowed=false', () => pm.expect(body.allowed).to.be.false);",
      "pm.test('violaciones 422N en name', () => { const codes = body.violations.map((v) => v.code); pm.expect(codes).to.eql(['MANI-CAT-422N', 'MANI-CAT-422N']); pm.expect(body.violations.every((v) => v.field === 'name')).to.be.true; });",
    ],
  }),
  evaluateRequest('CREATE inválida: nombre de 61 caracteres (MANI-CAT-422N)', {
    body: { context: { operation: 'CREATE', name: 'A'.repeat(61), flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('61 caracteres rechaza', () => { pm.expect(body.allowed).to.be.false; pm.expect(body.violations[0].code).to.eql('MANI-CAT-422N'); });",
    ],
  }),
  evaluateRequest('CREATE inválida: flujo operativo desconocido (MANI-CAT-422F)', {
    body: { context: { operation: 'CREATE', name: 'Jardinería', flujoOperativo: 'OTRO' } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('422F en flujoOperativo', () => { pm.expect(body.allowed).to.be.false; pm.expect(body.violations).to.have.lengthOf(1); pm.expect(body.violations[0]).to.include({ code: 'MANI-CAT-422F', field: 'flujoOperativo' }); });",
    ],
  }),
  evaluateRequest('UPDATE parcial: solo evalúa el nombre enviado', {
    body: { categoryId: 'cat-qa-1', context: { operation: 'UPDATE', name: 'Plomería Residencial' } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('aprueba sin exigir flujo', () => { pm.expect(body.allowed).to.be.true; pm.expect(body.normalized.flujoOperativo).to.be.null; pm.expect(body.categoryId).to.eql('cat-qa-1'); });",
    ],
  }),
  evaluateRequest('OPERATE con categoría inactiva (MANI-CAT-422C)', {
    token: '{{allyTokenA}}',
    body: { categoryId: 'cat-qa-1', context: { operation: 'OPERATE', active: false } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('422C', () => { pm.expect(body.allowed).to.be.false; pm.expect(body.violations[0]).to.include({ code: 'MANI-CAT-422C', field: 'active' }); });",
    ],
  }),
  evaluateRequest('OPERATE con categoría activa: un aliado puede evaluarla', {
    token: '{{allyTokenA}}',
    body: { categoryId: 'cat-qa-1', context: { operation: 'OPERATE', active: true } },
    asserts: [...evaluationAsserts(), "pm.test('aprueba', () => pm.expect(body.allowed).to.be.true);"],
  }),
  evaluateRequest('Autorización: un aliado no puede evaluar CREATE (403 FORBIDDEN)', {
    token: '{{allyTokenA}}',
    body: { context: { operation: 'CREATE', name: 'Plomería', flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: errorAsserts(403, 'FORBIDDEN'),
  }),
  evaluateRequest('Tenant: X-Tenant-Id enviado por el cliente se ignora (gana el claim)', {
    extraHeaders: [{ key: 'X-Tenant-Id', value: '{{tenantB}}' }],
    body: { context: { operation: 'CREATE', name: 'Plomería', flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: [
      ...evaluationAsserts(),
      "pm.test('no usa el tenant falsificado', () => pm.expect(body.tenantId).to.not.eql(pm.variables.get('tenantB')));",
    ],
  }),
  evaluateRequest('Tenant: tenantId de otro tenant en el cuerpo (403 TENANT_MISMATCH)', {
    body: { tenantId: '{{tenantB}}', context: { operation: 'CREATE', name: 'Plomería', flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: errorAsserts(403, 'TENANT_MISMATCH'),
  }),
  evaluateRequest('Sin JWT: el Gateway responde 401', {
    token: null,
    body: { context: { operation: 'CREATE', name: 'Plomería', flujoOperativo: 'TARIFA_ESTANDAR' } },
    asserts: [expectStatus(401)],
  }),
  evaluateRequest('Petición inválida: operación desconocida (400 VALIDATION_ERROR)', {
    body: { context: { operation: 'DELETE' } },
    asserts: errorAsserts(400, 'VALIDATION_ERROR'),
  }),
  evaluateRequest('Petición inválida: OPERATE sin active (400 VALIDATION_ERROR)', {
    token: '{{allyTokenA}}',
    body: { context: { operation: 'OPERATE' } },
    asserts: errorAsserts(400, 'VALIDATION_ERROR'),
  }),
  evaluateRequest('Petición inválida: sin context (400 VALIDATION_ERROR)', {
    body: {},
    asserts: errorAsserts(400, 'VALIDATION_ERROR'),
  }),
];

const collection = {
  info: {
    name: 'MANI-Rules (contrato de reglas de categoría)',
    description:
      'Generada por scripts/generate-rules-collection.js desde docs/openapi/rules.yaml (US-03.1.1-M6). Corre contra el Gateway real; no editar a mano.',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
  },
  event: [{ listen: 'prerequest', script: { type: 'text/javascript', exec: SIGN_TOKENS } }],
  variable: [
    { key: 'baseUrl', value: 'http://localhost' },
    { key: 'jwtSecret', value: 'dev-jwt-secret-insecure-32chars!!' },
    { key: 'tenantA', value: '10000000-0000-4000-8000-000000000011' },
    { key: 'tenantB', value: '10000000-0000-4000-8000-000000000021' },
  ],
  item: [{ name: 'Category Rules', item: items }],
};

fs.writeFileSync(OUTPUT_PATH, `${JSON.stringify(collection, null, 2)}\n`);
console.log(`✔ Colección generada: ${path.relative(process.cwd(), OUTPUT_PATH)} (${items.length} requests)`);
