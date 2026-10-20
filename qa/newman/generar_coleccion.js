// Genera la colección Newman de regresión del Sprint 4 contra QA (SCRUM-1267 / SCRUM-1277 / SCRUM-1279).
//
// Uso: node qa/newman/generar_coleccion.js
// Salida: qa/newman/mani_regresion_sprint4.postman_collection.json
//
// Los tokens no viven aquí: la colección usa {{token_*}}, que el ejecutor firma en la VM de QA
// y pasa como variables de entorno de Newman (qa/ejecutar_newman_qa.sh).
const fs = require('node:fs');
const path = require('node:path');

const SALIDA = path.join(__dirname, 'mani_regresion_sprint4.postman_collection.json');

// Datos de MANI-QA verificados el 20 oct 2026 (tenants acme-servicios y nova-mantenimiento), salvo aliado_t1b:
// ese aliado no está en supabase/seed/seed_qa_multitenant.sql y se agrega a la semilla en la Fase B.
// Los documentos legales de cada tenant se leen en la corrida (856-00 y 856-01), no se fijan aquí.
const D = {
  tenant_t1: '10000000-0000-4000-8000-000000000011',
  tenant_t2: '10000000-0000-4000-8000-000000000021',
  categoria_t1: '60000000-0000-4000-8000-000000000011',
  categoria_t2: '60000000-0000-4000-8000-000000000021',
  cliente_t1: '40000000-0000-4000-8000-000000000011',
  cliente_t2: '40000000-0000-4000-8000-000000000021',
  sitio_t1: '70000000-0000-4000-8000-000000000011',
  sitio_t2: '70000000-0000-4000-8000-000000000021',
  aliado_t1: '50000000-0000-4000-8000-000000000011',
  aliado_t2: '50000000-0000-4000-8000-000000000021',
  zona_cobertura: '20000000-0000-4000-8000-000000000002',
  solicitud_poc: 'a0000000-0000-4000-8000-900000000001',
};

// Contraseña de los registros de prueba (856-04 y 1063-01): se genera al azar en cada corrida (preparación de la
// colección), no se escribe en el código. Ambos casos se rechazan antes de crear el usuario.
const CONTRASENA_PRUEBA = '{{contrasena_prueba}}';

const CORE = '{{base_url}}/api/v1/core';
const DISPATCH = '{{base_url}}/api/v1/dispatch';
const RULES = '{{base_url}}/api/v1/rules';

// Cada caso: id (historia-secuencia), historia, nombre, metodo, url, token, cuerpo,
// esperado (códigos aceptados), guardar (variable <- expresión sobre json) y extra (aserciones JS).
const CASOS = [
  // ---------- Perímetro y autenticación (todas las historias) ----------
  { id: 'PER-01', historia: 'PERIMETRO', nombre: 'Salud del Gateway', metodo: 'GET', url: '{{base_url}}/health', esperado: [200] },
  { id: 'PER-02', historia: 'PERIMETRO', nombre: 'Salud de Core con base conectada', metodo: 'GET', url: `${CORE}/health`, esperado: [200],
    extra: "pm.test('PER-02 base de datos conectada', () => pm.expect(pm.response.json().database.connected).to.eql(true));" },
  { id: 'PER-03', historia: 'PERIMETRO', nombre: 'Salud de Rules', metodo: 'GET', url: `${RULES}/health`, esperado: [200] },
  { id: 'PER-04', historia: 'PERIMETRO', nombre: 'Salud de Dispatch', metodo: 'GET', url: `${DISPATCH}/health`, esperado: [200] },
  { id: 'PER-05', historia: 'PERIMETRO', nombre: 'dev-token no existe fuera de desarrollo', metodo: 'POST', url: `${CORE}/auth/dev-token`,
    cuerpo: { tenantId: D.tenant_t1, role: 'ADMIN_TENANT' }, esperado: [401, 403, 404] },
  { id: 'PER-06', historia: 'PERIMETRO', nombre: 'Ruta protegida sin token responde 401', metodo: 'GET', url: `${CORE}/profiles/me`, esperado: [401] },
  { id: 'PER-07', historia: 'PERIMETRO', nombre: 'X-Correlation-ID presente en la respuesta', metodo: 'GET', url: `${CORE}/health`, esperado: [200],
    extra: "pm.test('PER-07 correlation id', () => pm.expect(pm.response.headers.get('X-Correlation-ID')).to.be.a('string'));" },

  // ---------- Casos cross-tenant B1-B6 (SCRUM-1105 / SCRUM-1279 / QAS-01) ----------
  { id: 'B1-01', historia: 'CROSS_TENANT', nombre: 'B1 lectura: admin t1 no lee sitios de un cliente de t2', metodo: 'GET',
    url: `${CORE}/clients/${D.cliente_t2}/sites`, token: 'admin_t1', esperado: [403, 404] },
  { id: 'B2-01', historia: 'CROSS_TENANT', nombre: 'B2 listado: categorías de admin t1 sin ids de t2', metodo: 'GET',
    url: `${CORE}/catalog/categories`, token: 'admin_t1', esperado: [200],
    extra: `pm.test('B2-01 sin categorias de t2', () => pm.expect(JSON.stringify(pm.response.json())).to.not.include('${D.categoria_t2}'));` },
  { id: 'B3-01', historia: 'CROSS_TENANT', nombre: 'B3 escritura: admin t1 no configura reglas del sitio de t2', metodo: 'PUT',
    url: `${CORE}/sites/${D.sitio_t2}/rules`, token: 'admin_t1', cuerpo: { instruccionesIngreso: 'QA cross-tenant' }, esperado: [403, 404] },
  { id: 'B4-01', historia: 'CROSS_TENANT', nombre: 'B4 control: borrar una ausencia inexistente responde 404 (no prueba aislamiento; el borrado ajeno real es 855-04)', metodo: 'DELETE',
    url: `${CORE}/profiles/me/unavailability/00000000-0000-4000-8000-0000000000aa`, token: 'aliado_t1', esperado: [403, 404] },
  { id: 'B5-01', historia: 'CROSS_TENANT', nombre: 'B5 token expirado responde 401', metodo: 'GET', url: `${CORE}/profiles/me`, token: 'expirado', esperado: [401] },
  { id: 'B5-02', historia: 'CROSS_TENANT', nombre: 'B5 token con firma alterada responde 401', metodo: 'GET', url: `${CORE}/profiles/me`, token: 'alterado', esperado: [401] },
  { id: 'B5-03', historia: 'CROSS_TENANT', nombre: 'B5 token sin tenant_id responde 401', metodo: 'GET', url: `${CORE}/profiles/me`, token: 'sin_tenant', esperado: [401] },
  { id: 'B5-04', historia: 'CROSS_TENANT', nombre: 'B5 X-Tenant-Id del cliente no gana sobre el claim', metodo: 'GET',
    url: `${CORE}/catalog/categories`, token: 'admin_t1', headers: { 'X-Tenant-Id': D.tenant_t2 }, esperado: [200],
    extra: `pm.test('B5-04 sigue viendo solo t1', () => pm.expect(JSON.stringify(pm.response.json())).to.not.include('${D.categoria_t2}'));` },
  { id: 'B6-01', historia: 'CROSS_TENANT', nombre: 'B6 KYC: admin t1 no ve la verificación de un aliado de t2', metodo: 'GET',
    url: `${CORE}/aliados/${D.aliado_t2}/verificacion`, token: 'admin_t1', esperado: [403, 404] },

  // ---------- SCRUM-850 Registrar empleado directo ----------
  { id: '850-01', historia: 'SCRUM-850', nombre: 'Admin t1 registra un empleado directo', metodo: 'POST', url: `${CORE}/allies/employees`, token: 'admin_t1',
    cuerpo: { nombreCompleto: 'Empleado QA {{corrida}}', email: 'empleado.{{corrida}}@qa.mani.test', telefono: '3001234567',
      tipoDocumento: 'CC', numeroDocumento: '9{{corrida}}', categoriaId: D.categoria_t1 }, esperado: [201],
    extra: `pm.test('850-01 empleado directo verificado en t1 con su categoria', () => { const e = pm.response.json().employee || {};
      pm.expect(e.tenantId).to.eql('${D.tenant_t1}'); pm.expect(e.tipo).to.eql('EMPLEADO_DIRECTO');
      pm.expect(e.estadoVerificacion).to.eql('VERIFICADO'); pm.expect(e.categoriaId).to.eql('${D.categoria_t1}'); });` },
  { id: '850-02', historia: 'SCRUM-850', nombre: 'Correo repetido se rechaza', metodo: 'POST', url: `${CORE}/allies/employees`, token: 'admin_t1',
    cuerpo: { nombreCompleto: 'Empleado QA {{corrida}}', email: 'empleado.{{corrida}}@qa.mani.test', telefono: '3001234567',
      tipoDocumento: 'CC', numeroDocumento: '8{{corrida}}', categoriaId: D.categoria_t1 }, esperado: [400, 409, 422] },
  { id: '850-03', historia: 'SCRUM-850', nombre: 'Un cliente no puede registrar empleados', metodo: 'POST', url: `${CORE}/allies/employees`, token: 'cliente_t1',
    cuerpo: { nombreCompleto: 'No permitido', email: 'np.{{corrida}}@qa.mani.test', tipoDocumento: 'CC', numeroDocumento: '7{{corrida}}' }, esperado: [403] },
  { id: '850-04', historia: 'SCRUM-850', nombre: 'Categoría de otro tenant se rechaza', metodo: 'POST', url: `${CORE}/allies/employees`, token: 'admin_t1',
    cuerpo: { nombreCompleto: 'Empleado Cruce {{corrida}}', email: 'cruce.{{corrida}}@qa.mani.test', telefono: '3001234567',
      tipoDocumento: 'CC', numeroDocumento: '6{{corrida}}', categoriaId: D.categoria_t2 }, esperado: [400, 403, 404, 422] },

  // ---------- SCRUM-852 Cliente empresa con múltiples sitios ----------
  { id: '852-00', historia: 'SCRUM-852', nombre: 'Admin t1 registra un cliente empresa con una sede', metodo: 'POST', url: `${CORE}/clients/company`, token: 'admin_t1',
    cuerpo: { razonSocial: 'Empresa QA {{corrida}} SAS', nit: '901{{corrida}}', email: 'empresa.cliente.{{corrida}}@qa.mani.test', telefono: '6011234567',
      nombreRepresentante: 'Representante QA', sitios: [{ nombre: 'Sede principal QA', direccion: 'Carrera 7 # 72-10 Bogota', zonaId: D.zona_cobertura }] },
    esperado: [201], guardar: { cliente_empresa: 'json.client && json.client.id' } },
  { id: '852-01', historia: 'SCRUM-852', nombre: 'Lista las sedes del cliente empresa', metodo: 'GET', url: `${CORE}/clients/{{cliente_empresa}}/sites`, token: 'admin_t1', esperado: [200],
    extra: "pm.test('852-01 el cliente nuevo tiene una sede', () => pm.expect(pm.response.json().totalSitios).to.eql(1));" },
  { id: '852-02', historia: 'SCRUM-852', nombre: 'Agrega una segunda sede al cliente empresa', metodo: 'POST', url: `${CORE}/clients/{{cliente_empresa}}/sites`, token: 'admin_t1',
    cuerpo: { nombre: 'Sede norte QA {{corrida}}', direccion: 'Calle 140 # 15-20 Bogota', zonaId: D.zona_cobertura, contactoNombre: 'QA', contactoTelefono: '3001234567' }, esperado: [201],
    extra: "pm.test('852-02 la sede queda asociada al cliente empresa', () => pm.expect((pm.response.json().sitio || {}).clienteId).to.eql(pm.collectionVariables.get('cliente_empresa')));" },
  { id: '852-04', historia: 'SCRUM-852', nombre: 'NIT repetido en el mismo tenant se rechaza', metodo: 'POST', url: `${CORE}/clients/company`, token: 'admin_t1',
    cuerpo: { razonSocial: 'Empresa QA duplicada', nit: '901{{corrida}}', email: 'empresa.dup.{{corrida}}@qa.mani.test', sitios: [] }, esperado: [400, 409, 422] },
  { id: '852-05', historia: 'SCRUM-852', nombre: 'Admin t2 no ve las sedes del cliente empresa de t1', metodo: 'GET', url: `${CORE}/clients/{{cliente_empresa}}/sites`, token: 'admin_t2', esperado: [403, 404] },
  { id: '852-03', historia: 'SCRUM-852', nombre: 'Un aliado no puede agregar sitios', metodo: 'POST', url: `${CORE}/clients/${D.cliente_t1}/sites`, token: 'aliado_t1',
    cuerpo: { nombre: 'No permitido', direccion: 'Calle 1 # 2-3', zonaId: D.zona_cobertura }, esperado: [403] },

  // ---------- SCRUM-853 Reglas contextuales del sitio ----------
  { id: '853-01', historia: 'SCRUM-853', nombre: 'Cliente t1 configura reglas de su sitio', metodo: 'PUT', url: `${CORE}/sites/${D.sitio_t1}/rules`, token: 'cliente_t1',
    cuerpo: { horario: { dias: ['LUNES', 'MARTES', 'MIERCOLES', 'JUEVES', 'VIERNES'], horaInicio: '08:00', horaFin: '17:00' },
      permisosRequeridos: ['ARL'], elementosProteccion: ['CASCO'], instruccionesIngreso: 'Registrarse en porteria (QA {{corrida}})',
      requiereAprobacionPrevia: false, contactoAcceso: 'Porteria 3001234567' }, esperado: [200] },
  { id: '853-02', historia: 'SCRUM-853', nombre: 'Aliado t1 sin servicio asignado no lee las reglas del sitio', metodo: 'GET', url: `${CORE}/sites/${D.sitio_t1}/rules`, token: 'aliado_t1b', esperado: [403] },
  { id: '853-03', historia: 'SCRUM-853', nombre: 'Aliado t2 no lee reglas del sitio de t1', metodo: 'GET', url: `${CORE}/sites/${D.sitio_t1}/rules`, token: 'aliado_t2', esperado: [403, 404] },

  // ---------- SCRUM-854 Editar perfil propio ----------
  { id: '854-01', historia: 'SCRUM-854', nombre: 'Cliente t1 consulta su perfil', metodo: 'GET', url: `${CORE}/profiles/me`, token: 'cliente_t1', esperado: [200] },
  { id: '854-02', historia: 'SCRUM-854', nombre: 'Cliente t1 edita su teléfono', metodo: 'PATCH', url: `${CORE}/profiles/me`, token: 'cliente_t1',
    cuerpo: { telefono: '3009876543' }, esperado: [200],
    extra: "pm.test('854-02 el telefono queda actualizado', () => pm.expect((pm.response.json().profile || {}).phone).to.eql('3009876543'));" },
  { id: '854-03', historia: 'SCRUM-854', nombre: 'No se puede cambiar el rol desde el perfil', metodo: 'PATCH', url: `${CORE}/profiles/me`, token: 'cliente_t1',
    cuerpo: { rol: 'ADMIN_TENANT', tenantId: D.tenant_t2 }, esperado: [200, 400, 403, 422],
    extra: "pm.test('854-03 rol sin cambio', () => pm.expect(JSON.stringify(pm.response.json())).to.not.include('ADMIN_TENANT'));" },

  // ---------- SCRUM-855 Disponibilidad del aliado ----------
  { id: '855-01', historia: 'SCRUM-855', nombre: 'Aliado t1 registra una ausencia', metodo: 'POST', url: `${CORE}/profiles/me/unavailability`, token: 'aliado_t1',
    cuerpo: { startsAt: '{{inicio_ausencia}}', endsAt: '{{fin_ausencia}}', reason: 'VACACIONES', note: 'QA {{corrida}}' }, esperado: [201],
    guardar: { ausencia_id: 'json.absence ? json.absence.id : (json.id || (json.data && json.data.id))' },
    extra: "pm.test('855-01 la ausencia queda con el motivo enviado', () => { const a = pm.response.json().data || {}; pm.expect(a.id).to.be.a('string'); pm.expect(a.reason).to.eql('VACACIONES'); });" },
  { id: '855-02', historia: 'SCRUM-855', nombre: 'Aliado t1 lista sus ausencias', metodo: 'GET', url: `${CORE}/profiles/me/unavailability`, token: 'aliado_t1', esperado: [200] },
  { id: '855-03', historia: 'SCRUM-855', nombre: 'Motivo fuera del catálogo se rechaza', metodo: 'POST', url: `${CORE}/profiles/me/unavailability`, token: 'aliado_t1',
    cuerpo: { startsAt: '{{inicio_ausencia}}', endsAt: '{{fin_ausencia}}', reason: 'PASEO' }, esperado: [400, 422] },
  { id: '855-04', historia: 'SCRUM-855', nombre: 'Aliado t2 no borra la ausencia de t1', metodo: 'DELETE', url: `${CORE}/profiles/me/unavailability/{{ausencia_id}}`, token: 'aliado_t2', esperado: [403, 404] },
  { id: '855-05', historia: 'SCRUM-855', nombre: 'Aliado t1 borra su ausencia', metodo: 'DELETE', url: `${CORE}/profiles/me/unavailability/{{ausencia_id}}`, token: 'aliado_t1', esperado: [204] },
  { id: '855-06', historia: 'SCRUM-855', nombre: 'Un cliente no gestiona disponibilidad', metodo: 'GET', url: `${CORE}/profiles/me/unavailability`, token: 'cliente_t1', esperado: [403] },

  // ---------- SCRUM-856 Términos y condiciones ----------
  // 856-00 y 856-01 leen el documento propio de cada tenant (tenantId del documento, no los globales con tenantId nulo).
  { id: '856-00', historia: 'SCRUM-856', nombre: 'Documentos legales activos del tenant t2 (preparación de 856-03)', metodo: 'GET', url: `${CORE}/legal/documents/active`,
    token: 'cliente_t2', headers: { 'X-Tenant-Slug': 'nova-mantenimiento' }, esperado: [200],
    guardar: { doc_legal_t2: `((json.data || []).find((d) => d.tenantId === '${D.tenant_t2}') || {}).id` } },
  { id: '856-01', historia: 'SCRUM-856', nombre: 'Documentos legales activos del tenant t1 (sesion iniciada)', metodo: 'GET', url: `${CORE}/legal/documents/active`,
    token: 'cliente_t1', headers: { 'X-Tenant-Slug': 'acme-servicios' }, esperado: [200],
    guardar: { doc_legal_t1: `((json.data || []).find((d) => d.tenantId === '${D.tenant_t1}') || {}).id` } },
  { id: '856-05', historia: 'SCRUM-856', nombre: 'Documentos legales visibles antes del registro (sin token)', metodo: 'GET', url: `${CORE}/legal/documents/active`,
    headers: { 'X-Tenant-Slug': 'acme-servicios' }, esperado: [200] },
  // El cliente t1 ya consintió en corridas anteriores: 856-02 puede devolver una lista vacía. La primera aceptación
  // de un usuario sin consentimiento no se cubre aquí (requiere un usuario nuevo en la semilla, Fase B).
  { id: '856-02', historia: 'SCRUM-856', nombre: 'Cliente t1 registra su consentimiento', metodo: 'POST', url: `${CORE}/legal/consents`, token: 'cliente_t1',
    cuerpo: { documentoLegalIds: ['{{doc_legal_t1}}'] }, esperado: [200, 201],
    extra: "pm.test('856-02 responde la lista de consentimientos creados', () => pm.expect(pm.response.json().consents).to.be.an('array'));" },
  { id: '856-06', historia: 'SCRUM-856', nombre: 'Repetir el consentimiento no crea registros duplicados', metodo: 'POST', url: `${CORE}/legal/consents`, token: 'cliente_t1',
    cuerpo: { documentoLegalIds: ['{{doc_legal_t1}}'] }, esperado: [200, 201],
    extra: "pm.test('856-06 sin consentimientos nuevos', () => pm.expect(pm.response.json().consents).to.have.lengthOf(0));" },
  { id: '856-03', historia: 'SCRUM-856', nombre: 'Consentimiento sobre un documento de t2 se rechaza', metodo: 'POST', url: `${CORE}/legal/consents`, token: 'cliente_t1',
    cuerpo: { documentoLegalIds: ['{{doc_legal_t2}}'] }, esperado: [400, 403, 404, 422],
    extra: "pm.test('856-03 rechazo por pertenencia al tenant', () => pm.expect(pm.response.json().code).to.eql('LEGAL_DOCUMENT_NOT_FOUND'));" },
  { id: '856-04', historia: 'SCRUM-856', nombre: 'Registro de aliado sin aceptar términos se rechaza', metodo: 'POST', url: `${CORE}/auth/register/ally`,
    headers: { 'X-Tenant-Slug': 'acme-servicios' }, cuerpo: { email: 'sinterminos.{{corrida}}@qa.mani.test', password: CONTRASENA_PRUEBA, acceptsTerms: false },
    esperado: [400, 422] },

  // ---------- SCRUM-858 / SCRUM-1069 Categorías ----------
  { id: '858-01', historia: 'SCRUM-858', nombre: 'Admin t1 lista categorías con conteo de aliados', metodo: 'GET', url: `${CORE}/catalog/categories`, token: 'admin_t1', esperado: [200],
    extra: "pm.test('858-01 trae alliesCount', () => pm.expect(JSON.stringify(pm.response.json())).to.include('alliesCount'));" },
  { id: '858-02', historia: 'SCRUM-858', nombre: 'Admin t1 crea una categoría (pasa por Rules)', metodo: 'POST', url: `${CORE}/catalog/categories`, token: 'admin_t1',
    cuerpo: { name: 'Categoria QA {{corrida}}', description: 'Creada por la regresion SCRUM-1267', flujoOperativo: 'TARIFA_ESTANDAR' }, esperado: [201],
    guardar: { categoria_nueva: 'json.category && json.category.id' },
    extra: `pm.test('858-02 categoria activa en t1 con el flujo enviado', () => { const c = pm.response.json().category || {};
      pm.expect(c.active).to.eql(true); pm.expect(c.tenantId).to.eql('${D.tenant_t1}'); pm.expect(c.flujoOperativo).to.eql('TARIFA_ESTANDAR'); });` },
  { id: '858-03', historia: 'SCRUM-858', nombre: 'Admin t1 desactiva la categoría', metodo: 'PATCH', url: `${CORE}/catalog/categories/{{categoria_nueva}}/deactivate`, token: 'admin_t1', esperado: [200],
    extra: "pm.test('858-03 queda inactiva', () => pm.expect((pm.response.json().category || {}).active).to.eql(false));" },
  { id: '858-04', historia: 'SCRUM-858', nombre: 'Categoría desactivada no aparece en la vitrina pública', metodo: 'GET', url: `${CORE}/catalog`,
    headers: { 'X-Tenant-Slug': 'acme-servicios' }, esperado: [200],
    extra: "pm.test('858-04 no aparece', () => pm.expect(JSON.stringify(pm.response.json())).to.not.include(pm.collectionVariables.get('categoria_nueva') || 'sin-id'));" },
  { id: '858-05', historia: 'SCRUM-858', nombre: 'Admin t1 reactiva la categoría', metodo: 'PATCH', url: `${CORE}/catalog/categories/{{categoria_nueva}}/activate`, token: 'admin_t1', esperado: [200],
    extra: "pm.test('858-05 queda activa', () => pm.expect((pm.response.json().category || {}).active).to.eql(true));" },
  { id: '858-06', historia: 'SCRUM-858', nombre: 'Un cliente no administra categorías', metodo: 'PATCH', url: `${CORE}/catalog/categories/{{categoria_nueva}}/deactivate`, token: 'cliente_t1', esperado: [403] },
  { id: '858-07', historia: 'SCRUM-858', nombre: 'Admin t2 no ve la categoría de t1', metodo: 'GET', url: `${CORE}/catalog/categories/{{categoria_nueva}}`, token: 'admin_t2', esperado: [403, 404] },
  { id: '1069-01', historia: 'SCRUM-1069', nombre: 'Vitrina pública por slug del tenant', metodo: 'GET', url: `${CORE}/catalog`, headers: { 'X-Tenant-Slug': 'acme-servicios' }, esperado: [200],
    extra: "pm.test('1069-01 con categorias', () => pm.expect((pm.response.json().categories || []).length).to.be.above(0));" },

  // ---------- SCRUM-1070 / SCRUM-1226 Reglas de categoría (Rules Java vía Core) ----------
  { id: '1070-01', historia: 'SCRUM-1070', nombre: 'Nombre de 2 caracteres se rechaza por Rules', metodo: 'POST', url: `${CORE}/catalog/categories`, token: 'admin_t1',
    cuerpo: { name: 'ab', description: 'invalida', flujoOperativo: 'TARIFA_ESTANDAR' }, esperado: [400, 422],
    extra: "pm.test('1070-01 codigo de Rules', () => pm.expect(pm.response.text()).to.include('MANI-CAT-422'));" },
  { id: '1070-02', historia: 'SCRUM-1070', nombre: 'Flujo operativo desconocido se rechaza por Rules', metodo: 'POST', url: `${CORE}/catalog/categories`, token: 'admin_t1',
    cuerpo: { name: 'Categoria Flujo {{corrida}}', flujoOperativo: 'INVENTADO' }, esperado: [400, 422] },
  { id: '1070-03', historia: 'SCRUM-1070', nombre: 'Rules directo: aliado no evalúa CREATE', metodo: 'POST', url: `${RULES}/categories/evaluate`, token: 'aliado_t1',
    cuerpo: { context: { operation: 'CREATE', name: 'Prueba QA', flujoOperativo: 'TARIFA_ESTANDAR' } }, esperado: [403] },

  // ---------- SCRUM-1066 Verificación de aliados (KYC) ----------
  { id: '1066-01', historia: 'SCRUM-1066', nombre: 'Admin t1 lista aliados por verificar', metodo: 'GET', url: `${CORE}/aliados/verificacion`, token: 'admin_t1', esperado: [200] },
  { id: '1066-02', historia: 'SCRUM-1066', nombre: 'Admin t1 ve el detalle de su aliado', metodo: 'GET', url: `${CORE}/aliados/${D.aliado_t1}/verificacion`, token: 'admin_t1', esperado: [200] },
  { id: '1066-03', historia: 'SCRUM-1066', nombre: 'Un aliado no lista verificaciones', metodo: 'GET', url: `${CORE}/aliados/verificacion`, token: 'aliado_t1', esperado: [403] },

  // ---------- SCRUM-1063 Registro de aliado empresa ----------
  // Cuerpo completo salvo los documentos: el rechazo debe ser por la Cámara de Comercio faltante, no por otro campo.
  { id: '1063-01', historia: 'SCRUM-1063', nombre: 'Registro de aliado empresa sin documentos se rechaza', metodo: 'POST', url: `${CORE}/auth/register/ally/company`,
    headers: { 'X-Tenant-Slug': 'acme-servicios' },
    cuerpo: { razonSocial: 'Empresa QA {{corrida}}', nit: '900{{corrida}}', nombreRepresentante: 'Representante QA', email: 'empresa.{{corrida}}@qa.mani.test',
      password: CONTRASENA_PRUEBA, telefono: '6011234567', acceptsTerms: true },
    esperado: [400, 422],
    extra: "pm.test('1063-01 rechazo por falta de camara de comercio', () => pm.expect(pm.response.json().error).to.match(/camara_comercio/i));" },

  // ---------- SCRUM-1072 Crear solicitud (Core) ----------
  { id: '1072-01', historia: 'SCRUM-1072', nombre: 'Cliente t1 crea una solicitud en su sitio', metodo: 'POST', url: `${CORE}/solicitudes`, token: 'cliente_t1',
    cuerpo: { categoriaId: D.categoria_t1, descripcion: 'Fuga en el lavamanos del bano principal (QA {{corrida}})', sitioId: D.sitio_t1, claveIdempotencia: '{{clave_idempotencia}}' },
    esperado: [201], guardar: { solicitud_t1: '(json.solicitud && json.solicitud.id) || json.id' },
    extra: `pm.test('1072-01 solicitud pendiente en el sitio y la categoria enviados', () => { const s = pm.response.json().solicitud || {};
      pm.expect(s.estado).to.eql('PENDIENTE'); pm.expect(s.sitioId).to.eql('${D.sitio_t1}'); pm.expect(s.categoriaId).to.eql('${D.categoria_t1}'); });` },
  { id: '1072-02', historia: 'SCRUM-1072', nombre: 'Misma clave de idempotencia no duplica', metodo: 'POST', url: `${CORE}/solicitudes`, token: 'cliente_t1',
    cuerpo: { categoriaId: D.categoria_t1, descripcion: 'Fuga en el lavamanos del bano principal (QA {{corrida}})', sitioId: D.sitio_t1, claveIdempotencia: '{{clave_idempotencia}}' },
    esperado: [200, 201],
    extra: "pm.test('1072-02 mismo id', () => pm.expect(JSON.stringify(pm.response.json())).to.include(pm.collectionVariables.get('solicitud_t1') || 'sin-id'));" },
  { id: '1072-03', historia: 'SCRUM-1072', nombre: 'Descripción corta se rechaza', metodo: 'POST', url: `${CORE}/solicitudes`, token: 'cliente_t1',
    cuerpo: { categoriaId: D.categoria_t1, descripcion: 'corta', sitioId: D.sitio_t1 }, esperado: [400, 422] },
  { id: '1072-04', historia: 'SCRUM-1072', nombre: 'Un aliado no publica solicitudes', metodo: 'POST', url: `${CORE}/solicitudes`, token: 'aliado_t1',
    cuerpo: { categoriaId: D.categoria_t1, descripcion: 'Intento de aliado publicando una solicitud', sitioId: D.sitio_t1 }, esperado: [403] },
  { id: '1072-05', historia: 'SCRUM-1072', nombre: 'Categoría de t2 se rechaza para cliente t1', metodo: 'POST', url: `${CORE}/solicitudes`, token: 'cliente_t1',
    cuerpo: { categoriaId: D.categoria_t2, descripcion: 'Intento con categoria de otro tenant QA', sitioId: D.sitio_t1 }, esperado: [400, 403, 404, 422] },

  // ---------- SCRUM-861 / SCRUM-862 Aliados elegibles ----------
  { id: '861-01', historia: 'SCRUM-861', nombre: 'Match de aliados por cobertura y categoría', metodo: 'POST', url: `${DISPATCH}/match`, token: 'admin_t1',
    cuerpo: { requestId: '{{solicitud_t1}}', zonaId: D.zona_cobertura, categoriaId: D.categoria_t1 }, esperado: [200],
    extra: `pm.test('861-01 incluye aliado t1', () => pm.expect(pm.response.text()).to.include('${D.aliado_t1}'));` },
  { id: '861-02', historia: 'SCRUM-861', nombre: 'Match sin token responde 401', metodo: 'POST', url: `${DISPATCH}/match`,
    cuerpo: { zonaId: D.zona_cobertura, categoriaId: D.categoria_t1 }, esperado: [401] },
  { id: '862-01', historia: 'SCRUM-862', nombre: 'Elegibles filtrados por PERSONA_NATURAL', metodo: 'GET',
    url: `${DISPATCH}/requests/{{solicitud_t1}}/eligible-allies?zonaId=${D.zona_cobertura}&categoriaId=${D.categoria_t1}&tipo=PERSONA_NATURAL`, token: 'admin_t1', esperado: [200],
    extra: `pm.test('862-01 no trae aliados de t2', () => pm.expect(pm.response.text()).to.not.include('${D.aliado_t2}'));` },
  { id: '862-02', historia: 'SCRUM-862', nombre: 'Tipo inválido se rechaza', metodo: 'GET',
    url: `${DISPATCH}/requests/{{solicitud_t1}}/eligible-allies?zonaId=${D.zona_cobertura}&categoriaId=${D.categoria_t1}&tipo=MARCIANO`, token: 'admin_t1', esperado: [400, 422] },

  // ---------- SCRUM-1073 Orquestación de despacho ----------
  { id: '1073-01', historia: 'SCRUM-1073', nombre: 'Orquesta el despacho de la solicitud t1', metodo: 'POST', url: `${DISPATCH}/requests/orchestrate`, token: 'admin_t1',
    cuerpo: { requestId: '{{solicitud_t1}}' }, esperado: [200, 201, 202] },
  { id: '1073-02', historia: 'SCRUM-1073', nombre: 'Ruta interna allies/eligible cerrada desde fuera', metodo: 'GET', url: `${CORE}/allies/eligible`, token: 'admin_t1', esperado: [403, 404] },
  { id: '1073-03', historia: 'SCRUM-1073', nombre: 'Ruta interna notifications cerrada desde fuera', metodo: 'POST', url: `${CORE}/notifications`, token: 'admin_t1', cuerpo: {}, esperado: [403, 404] },

  // ---------- SCRUM-1074 Aceptar sin doble asignación ----------
  { id: '1074-01', historia: 'SCRUM-1074', nombre: 'Aliado t1 acepta la solicitud t1', metodo: 'POST', url: `${DISPATCH}/requests/{{solicitud_t1}}/accept`, token: 'aliado_t1', esperado: [200],
    extra: `pm.test('1074-01 asignada al aliado t1', () => { const j = pm.response.json(); pm.expect(j.status).to.eql('ASSIGNED'); pm.expect(j.assignedAllyId).to.eql('${D.aliado_t1}'); });` },
  { id: '1074-02', historia: 'SCRUM-1074', nombre: 'Reaceptación del mismo aliado es idempotente', metodo: 'POST', url: `${DISPATCH}/requests/{{solicitud_t1}}/accept`, token: 'aliado_t1', esperado: [200],
    extra: `pm.test('1074-02 mismo aliado asignado', () => pm.expect(pm.response.text()).to.include('${D.aliado_t1}'));` },
  { id: '853-04', historia: 'SCRUM-853', carpeta: 'SCRUM-1074', nombre: 'Aliado t1 con el servicio asignado lee las reglas del sitio (criterio de aceptacion de 853)', metodo: 'GET',
    url: `${CORE}/sites/${D.sitio_t1}/rules`, token: 'aliado_t1', esperado: [200],
    extra: "pm.test('853-04 trae las reglas destacadas', () => pm.expect(pm.response.text()).to.include('reglasDestacadas'));" },
  // Excluidos de la regresión: usan la solicitud PoC que QAS-07 (SCRUM-1266) necesita en PENDIENTE. Se reemplazan en
  // la Fase B por una solicitud creada en la corrida y un segundo aliado elegible de t1.
  { id: '1074-05', historia: 'SCRUM-1074', nombre: 'Aliado PoC 1 acepta la solicitud PoC', metodo: 'POST', url: `${DISPATCH}/requests/${D.solicitud_poc}/accept`, token: 'aliado_poc1', esperado: [200],
    excluido: 'Usa la solicitud PoC reservada a QAS-07 (SCRUM-1266)' },
  { id: '1074-06', historia: 'SCRUM-1074', nombre: 'Un segundo aliado no puede aceptar la misma solicitud (409)', metodo: 'POST', url: `${DISPATCH}/requests/${D.solicitud_poc}/accept`, token: 'aliado_poc2', esperado: [409],
    excluido: 'Usa la solicitud PoC reservada a QAS-07 (SCRUM-1266)' },
  { id: '1074-03', historia: 'SCRUM-1074', nombre: 'Aliado de t2 no acepta solicitudes de t1', metodo: 'POST', url: `${DISPATCH}/requests/{{solicitud_t1}}/accept`, token: 'aliado_t2', esperado: [403, 404, 409] },
  { id: '1074-04', historia: 'SCRUM-1074', nombre: 'Un cliente no acepta solicitudes', metodo: 'POST', url: `${DISPATCH}/requests/{{solicitud_t1}}/accept`, token: 'cliente_t1', esperado: [403] },
];

// Variables que un caso guarda para otro. Si una falta, el caso que la usa falla en su precondición en lugar de
// pasar con un id vacío (un 404 por id vacío no prueba aislamiento).
const VARIABLES_GUARDADAS = new Set(CASOS.flatMap((c) => Object.keys(c.guardar || {})));

function itemDe(caso) {
  const encabezados = [{ key: 'X-Correlation-ID', value: `qa1267-${caso.id}-{{corrida}}` }];
  if (caso.token) encabezados.push({ key: 'Authorization', value: `Bearer {{token_${caso.token}}}` });
  if (caso.cuerpo) encabezados.push({ key: 'Content-Type', value: 'application/json' });
  for (const [k, v] of Object.entries(caso.headers || {})) encabezados.push({ key: k, value: v });

  const usadas = [...new Set([...JSON.stringify([caso.url, caso.cuerpo || null]).matchAll(/{{(\w+)}}/g)].map((m) => m[1]))]
    .filter((v) => VARIABLES_GUARDADAS.has(v));
  const prueba = usadas.map((v) => `pm.test('${caso.id} precondicion: ${v} definida', () => pm.expect(pm.collectionVariables.get('${v}')).to.be.a('string').and.not.empty);`);
  prueba.push(
    `pm.test('${caso.id} estado esperado ${caso.esperado.join('/')}', () => pm.expect(pm.response.code).to.be.oneOf([${caso.esperado.join(', ')}]));`,
  );
  for (const [variable, expresion] of Object.entries(caso.guardar || {})) {
    prueba.push(`try { const json = pm.response.json(); const v = ${expresion}; if (v) pm.collectionVariables.set('${variable}', v); } catch (e) {}`);
  }
  if (caso.extra) prueba.push(caso.extra);

  const item = {
    name: `[${caso.id}] ${caso.historia} - ${caso.nombre}`,
    event: [{ listen: 'test', script: { type: 'text/javascript', exec: prueba } }],
    request: { method: caso.metodo, header: encabezados, url: caso.url },
  };
  if (caso.cuerpo) item.request.body = { mode: 'raw', raw: JSON.stringify(caso.cuerpo, null, 2) };
  return item;
}

const EXCLUIDOS = CASOS.filter((c) => c.excluido);
const carpetas = [];
for (const caso of CASOS.filter((c) => !c.excluido)) {
  const nombre_carpeta = caso.carpeta || caso.historia;
  let carpeta = carpetas.find((c) => c.name === nombre_carpeta);
  if (!carpeta) {
    carpeta = { name: nombre_carpeta, item: [] };
    carpetas.push(carpeta);
  }
  carpeta.item.push(itemDe(caso));
}

const preparacion = [
  "if (!pm.collectionVariables.get('corrida')) pm.collectionVariables.set('corrida', String(Date.now()).slice(-8));",
  "if (!pm.collectionVariables.get('clave_idempotencia')) pm.collectionVariables.set('clave_idempotencia', require('uuid').v4());",
  "if (!pm.collectionVariables.get('contrasena_prueba')) pm.collectionVariables.set('contrasena_prueba', 'Qa-' + require('uuid').v4());",
  "const inicio = new Date(Date.now() + 30 * 864e5); const fin = new Date(Date.now() + 32 * 864e5);",
  "if (!pm.collectionVariables.get('inicio_ausencia')) { pm.collectionVariables.set('inicio_ausencia', inicio.toISOString()); pm.collectionVariables.set('fin_ausencia', fin.toISOString()); }",
];

const coleccion = {
  info: {
    name: 'MANI - Regresion Sprint 4 en QA (SCRUM-1267)',
    description: 'Regresion funcional, API y multi-tenant de las historias del Sprint 4 a traves del API Gateway de QA. Generada por qa/newman/generar_coleccion.js; no editar a mano.'
      + (EXCLUIDOS.length ? ` Casos excluidos: ${EXCLUIDOS.map((c) => `${c.id} (${c.excluido})`).join('; ')}.` : ''),
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
  },
  event: [{ listen: 'prerequest', script: { type: 'text/javascript', exec: preparacion } }],
  variable: [{ key: 'base_url', value: 'http://localhost' }],
  item: carpetas,
};

fs.writeFileSync(SALIDA, `${JSON.stringify(coleccion, null, 2)}\n`);
const incluidos = CASOS.length - EXCLUIDOS.length;
console.log(`Coleccion escrita: ${path.relative(process.cwd(), SALIDA)} (${incluidos} casos en ${carpetas.length} carpetas; ${EXCLUIDOS.length} excluidos: ${EXCLUIDOS.map((c) => c.id).join(', ') || 'ninguno'})`);
