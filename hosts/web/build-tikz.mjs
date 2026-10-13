// The released standalone editor supplies the visual canvas and embed protocol.
import { cp, mkdir, access } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const execute = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const editor = path.join(root, '.ci/visual-tikz-editor');
const freetikz = path.join(root, '.ci/freetikz');

async function run(command, args, cwd) {
  const child = execute(command, args, { cwd, maxBuffer: 16 * 1024 * 1024 });
  child.child.stdout.pipe(process.stdout);
  child.child.stderr.pipe(process.stderr);
  return child;
}

async function source(url, revision, directory) {
  try {
    await access(path.join(directory, '.git'));
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    await mkdir(directory, { recursive: true });
    await run('git', ['init'], directory);
    await run('git', ['remote', 'add', 'origin', url], directory);
  }
  let { stdout } = await execute('git', ['rev-parse', 'HEAD'], { cwd: directory })
    .catch(() => ({ stdout: '' }));
  if (stdout.trim() !== revision) {
    await run('git', ['fetch', '--depth', '1', 'origin', revision], directory);
    await run('git', ['checkout', '--detach', 'FETCH_HEAD'], directory);
    ({ stdout } = await execute('git', ['rev-parse', 'HEAD'], { cwd: directory }));
  }
  if (stdout.trim() !== revision) throw new Error(`Source revision differs in ${directory}`);
}

await source('https://github.com/dzackgarza/visual-tikz-editor.git', '73dddad8551ff5d48c2cb0886aac9efb01b1822c', editor);
await source('https://github.com/dzackgarza/freetikz.git', '9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68', freetikz);
const output = process.argv[2] ? path.resolve(root, process.argv[2]) : path.join(root, 'hosts/web/flutter/build/web/tikz-editor');
await mkdir(output, { recursive: true });
await cp(path.join(editor, 'vendor/tikz-editor/src'), output, { recursive: true });
await cp(path.join(editor, 'vendor/tikz-editor/LICENSE'), path.join(output, 'LICENSE'));

const runtime = process.argv[3] ? path.resolve(root, process.argv[3]) : null;
if (runtime) {
  await mkdir(runtime, { recursive: true });
  await run('bun', [
    'build', path.join(root, 'hosts/web/ipad-figure-generator.js'),
    '--target=browser', '--format=iife',
    `--outfile=${path.join(runtime, 'figure-generator.js')}`,
  ], root);
}
