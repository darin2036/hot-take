import {readFileSync, readdirSync, copyFileSync, mkdirSync} from 'node:fs';
import assert from 'node:assert/strict';
const manifest = JSON.parse(readFileSync('dist/manifest.json', 'utf8'));
assert.equal(manifest.manifest_version, 3);
assert.equal(manifest.incognito, 'not_allowed');
assert.equal(manifest.permissions, undefined);
assert.equal(manifest.host_permissions, undefined);
assert.equal(manifest.content_scripts, undefined);
assert.equal(manifest.action.default_popup, 'popup.html');
assert.ok(readFileSync('dist/popup.html', 'utf8').includes('assets/'));
assert.equal(manifest.background, undefined);
for (const name of readdirSync('dist/assets')) {
  const source = readFileSync(`dist/assets/${name}`, 'utf8');
  assert.ok(
    !/https?:\/\//.test(source.replaceAll('http://www.w3.org/2000/svg', '')),
    `Unexpected remote URL in ${name}`,
  );
}
console.log('Manifest and bundled network policy validated.');

copyFileSync('LICENSE', 'dist/LICENSE');

mkdirSync('dist/licenses', {recursive: true});
copyFileSync('licenses/lucide-LICENSE', 'dist/licenses/lucide-LICENSE');
