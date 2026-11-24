const test = require('node:test');
const assert = require('node:assert/strict');
const { muestra, UUID_MUESTRA } = require('../../scripts/contrato/muestras');

test('usa el ejemplo, el valor por omisión o el primer valor del catálogo', () => {
  assert.equal(muestra({ type: 'string', example: 'hola' }), 'hola');
  assert.equal(muestra({ type: 'integer', default: 20 }), 20);
  assert.equal(muestra({ type: 'string', enum: ['A', 'B'] }), 'A');
});

test('respeta el formato y los límites de cada tipo', () => {
  assert.equal(muestra({ type: 'string', format: 'uuid' }), UUID_MUESTRA);
  assert.equal(muestra({ type: 'string', minLength: 12 }).length, 12);
  assert.equal(muestra({ type: 'string', maxLength: 3 }).length, 3);
  assert.equal(muestra({ type: 'integer', minimum: 5 }), 5);
  assert.equal(muestra({ type: 'number', maximum: 0.5 }), 0.5);
  assert.equal(muestra({ type: 'boolean' }), true);
  assert.deepEqual(muestra({ type: 'array', minItems: 2, items: { type: 'integer' } }), [1, 1]);
  assert.deepEqual(muestra({ type: 'array', minItems: 1 }), [{}]);
});

test('arma solo los campos obligatorios que se pueden escribir', () => {
  const esquema = {
    type: 'object',
    required: ['id', 'nombre', 'ausente'],
    properties: { id: { type: 'string', readOnly: true }, nombre: { type: 'string' }, opcional: { type: 'string' } },
  };
  assert.deepEqual(muestra(esquema), { nombre: 'contrato' });
});

test('combina allOf y toma la primera alternativa de oneOf y anyOf', () => {
  const campo = (nombre) => ({ type: 'object', required: [nombre], properties: { [nombre]: { type: 'integer' } } });
  assert.deepEqual(muestra({ allOf: [campo('a'), { type: 'string' }, campo('b')] }), { a: 1, b: 1 });
  assert.deepEqual(muestra({ oneOf: [campo('a'), campo('b')] }), { a: 1 });
  assert.deepEqual(muestra({ anyOf: [campo('b')] }), { b: 1 });
});

test('corta un esquema recursivo en vez de expandirlo sin fin', () => {
  const nodo = { type: 'object', required: ['hijo'], properties: {} };
  nodo.properties.hijo = nodo;
  assert.match(JSON.stringify(muestra(nodo)), /null/);
  assert.deepEqual(muestra(), {});
});
