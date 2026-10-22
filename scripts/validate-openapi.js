const path = require('node:path');
const SwaggerParser = require('@apidevtools/swagger-parser');

const SPECS = ['core.yaml', 'rules.yaml'].map((file) => path.join(__dirname, '..', 'docs', 'openapi', file));

Promise.all(
  SPECS.map((specPath) =>
    SwaggerParser.validate(specPath).then((api) => {
      console.log(`✔ OpenAPI válido: ${api.info.title} (v${api.info.version})`);
      console.log(`  Paths: ${Object.keys(api.paths).join(', ')}`);
    })
  )
).catch((err) => {
  console.error(`✖ OpenAPI inválido: ${err.message}`);
  process.exit(1);
});
