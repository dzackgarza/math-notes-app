import { BusyTexRunner, LuaLatex } from 'texlyre-busytex';
import type { OpenNotebook } from './notebook.ts';
import type { FigurePdfReply } from './figure-pdf.worker.ts';
import { writeFiles } from '../storage/folder.ts';

const preambleFile = '.figure-preamble.tex';

export async function readFigurePreamble(root: FileSystemDirectoryHandle): Promise<string> {
  try {
    const file = await (await root.getFileHandle(preambleFile)).getFile();
    return new TextDecoder('utf-8', { fatal: true }).decode(await file.arrayBuffer());
  } catch (error) {
    if (error instanceof DOMException && error.name === 'NotFoundError') return '';
    throw error;
  }
}

export async function writeFigurePreamble(root: FileSystemDirectoryHandle, content: string, expected: string): Promise<void> {
  await navigator.locks.request('math-notes-files', async () => {
    if (await readFigurePreamble(root) !== expected) throw new Error('The project preamble changed. Reopen it before saving.');
    await writeFiles(root, [{ kind: 'write', path: preambleFile, bytes: new TextEncoder().encode(content) }]);
  });
}

export async function compileFigure(note: OpenNotebook, id: string, progress: (message: string) => void): Promise<void> {
  const source = note.document.figureSource(id);
  const preamble = await readFigurePreamble(note.root);
  const base = new URL('busytex/', document.baseURI).href.replace(/\/$/, '');
  const runner = new BusyTexRunner({
    busytexBasePath: base, initRetries: 0,
    preloadDataPackages: [`${base}/texlive-extra.js`], catalogDataPackages: [],
    onDownloadProgress: value => progress(`Loading compiler: ${Math.round(value.percent)}%`),
  });
  try {
    progress('Loading figure compiler…');
    await runner.initialize();
    const assets = await note.dir.getDirectoryHandle('assets');
    const additionalFiles: { path: string; content: Uint8Array }[] = [];
    for await (const [name, handle] of assets.entries()) {
      if (handle.kind === 'file') additionalFiles.push({ path: `assets/${name}`, content: new Uint8Array(await (await handle.getFile()).arrayBuffer()) });
    }
    progress('Compiling figure…');
    const result = await new LuaLatex(runner).compile({
      input: `\\documentclass[tikz,border=0pt]{standalone}\n${preamble}\n\\begin{document}\n${source}\n\\end{document}\n`,
      mainTexPath: 'figure.tex', additionalFiles, remoteEndpoint: '', shellEscape: false,
    });
    if (!result.success || !result.pdf) throw new Error(result.log || `TeX compilation failed with exit code ${result.exitCode}.`);
    progress('Preparing vector page view…');
    const worker = new Worker(new URL('./figure-pdf.worker.ts', import.meta.url), { type: 'module' });
    const vector = await new Promise<FigurePdfReply>((resolve, reject) => {
      worker.onmessage = (event: MessageEvent<FigurePdfReply>) => { worker.terminate(); resolve(event.data); };
      worker.onerror = event => { worker.terminate(); reject(new Error(event.message)); };
      worker.postMessage(result.pdf);
    });
    if ('error' in vector) throw new Error(vector.error);
    if (await readFigurePreamble(note.root) !== preamble) throw new Error('The project preamble changed during compilation. Compile again.');
    note.document.acceptFigure(id, { source, preamble, ...vector }, result.pdf);
    await note.saver.save();
    progress('Figure saved');
  } finally { runner.terminate(); }
}
