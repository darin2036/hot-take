import {mkdirSync, rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
mkdirSync('release', {recursive: true});
rmSync('release/hot-take-0.1.0.zip', {force: true});
execFileSync('zip', ['-qr', '../release/hot-take-0.1.0.zip', '.'], {cwd: 'dist'});
console.log('Created release/hot-take-0.1.0.zip (extension + static app).');
