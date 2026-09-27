// Selected BusyTeX builder and TeX Live input: docs/specs/tikz-drawing-mode.md.
import { access, appendFile, cp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const execute = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const build = process.env.MATH_NOTES_TEX_BUILD;
if (!build || !path.isAbsolute(build)) throw new Error('Set MATH_NOTES_TEX_BUILD to an absolute build directory with room for the TeX Live ISO, extraction, and native/WASM builds.');
const revision = 'f544a51a99e7d3978bb70608e927a9a23f96d4a7';
const isoName = 'texlive2026-20260301.iso';
const isoUrl = `https://mirror.ctan.org/systems/texlive/Images/${isoName}`;
const digest = '4a9071bb567c3bdd6443378dedc8e485aea4a2f1203ec8ed7c17f6787093b9c37636a037032c0be63352e3d0bf98cf5616dab19fdcd7cb83f766b3e085b620ff';

async function run(command, args, cwd = build) {
  const child = execute(command, args, { cwd, maxBuffer: 64 * 1024 * 1024 });
  child.child.stdout.pipe(process.stdout);
  child.child.stderr.pipe(process.stderr);
  await child;
}

try { await access(path.join(build, '.git')); }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
  await mkdir(path.dirname(build), { recursive: true });
  await run('git', ['clone', '--revision', revision, 'https://github.com/TeXlyre/texlyre-busytex-build.git', build], root);
}
const head = await execute('git', ['rev-parse', 'HEAD'], { cwd: build });
if (head.stdout.trim() !== revision) throw new Error('BusyTeX builder revision differs from the selected source.');
await mkdir(path.join(build, 'source'), { recursive: true });
const iso = path.join(build, 'source/texlive2026.iso');
let downloaded = 0;
try { downloaded = (await stat(iso)).size; }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
if (downloaded < 6784798720)
  await run('curl', ['--fail', '--location', '--continue-at', '-', '--output', iso, isoUrl]);
const hash = createHash('sha512');
for await (const bytes of createReadStream(iso)) hash.update(bytes);
if (hash.digest('hex') !== digest) throw new Error('The TeX Live ISO does not match its pinned SHA-512 digest.');
await run('make', ['build/texlive-extra.profile']);
const profile = path.join(build, 'build/texlive-extra.profile');
if (!(await readFile(profile, 'utf8')).split('\n').some(line => /^collection-pictures\s+1\s*$/.test(line)))
  await appendFile(profile, '\ncollection-pictures 1\n');
await run('make', ['-j2', `URL_texlive_full_iso=${isoUrl}`, 'build/wasm/texlive-extra.fmt-rebuilt']);
const output = path.join(root, '.ci/figure-compiler');
await mkdir(output, { recursive: true });
for (const file of ['busytex.js', 'busytex.wasm', 'texlive-extra.js', 'texlive-extra.data'])
  await cp(path.join(build, 'build/wasm', file), path.join(output, file));
for (const file of ['busytex_pipeline.js', 'busytex_worker.js'])
  await cp(path.join(build, 'web', file), path.join(output, file));
await cp(path.join(root, 'hosts/web/node_modules/texlyre-busytex/LICENSE'), path.join(output, 'LICENSE'));
await writeFile(path.join(output, 'manifest.json'), JSON.stringify({ builder: revision, iso: isoName, sha512: digest, profile: 'extra-plus-pictures', engine: 'LuaLaTeX' }, null, 2) + '\n');
