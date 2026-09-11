// Validate the generated files with Khronos's independent glTF validator.
const fs = require('node:fs');
const path = require('node:path');
const directory = path.resolve(process.argv[2] || 'build/gltf-preview');
const validator = require(path.join(directory, 'node_modules/gltf-validator'));
(async () => {
  const files = fs.readdirSync(directory).filter(name => name.endsWith('.glb'));
  if (!files.length) throw new Error('No GLB files found');
  let failures = 0;
  for (const name of files) {
    const report = await validator.validateBytes(new Uint8Array(fs.readFileSync(path.join(directory, name))));
    const { numErrors, numWarnings } = report.issues;
    console.log(`${name}: ${numErrors} errors, ${numWarnings} warnings`);
    if (numErrors || numWarnings) {
      failures++;
      console.log(JSON.stringify(report.issues.messages, null, 2));
    }
  }
  process.exitCode = failures ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
