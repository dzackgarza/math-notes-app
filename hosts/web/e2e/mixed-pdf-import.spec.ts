import { execFileSync } from 'node:child_process';
import { copyFile, readFile, unlink } from 'node:fs/promises';
import { test, expect } from '@playwright/test';
import { createTestNotebook, goToPage, penStroke, line, save } from './workflow-actions.ts';

test('mixed-size PDF pages retain their backgrounds, annotations, and sizes without the source file', async ({ page }, info) => {
  test.setTimeout(600_000);
  await page.goto('?root=opfs');
  await createTestNotebook(page, 'Papers');
  const source = info.outputPath('mixed-pages.pdf');
  await copyFile('e2e/fixtures/mixed-pages.pdf', source);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import PDF', exact: true }).click();
  await (await chooser).setFiles(source);
  await expect(page.getByText('1 / 3', { exact: true })).toBeVisible({ timeout: 300_000 });
  await unlink(source);

  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  const cdp = await page.context().newCDPSession(page);
  const bounds = (await canvas.boundingBox())!;
  await goToPage(page, 2);
  await penStroke(cdp, line(bounds.x + 160, bounds.x + 270, bounds.y + 240), .7);
  await save(page);
  await expect(page.getByRole('status', { name: /^Notebook save/ })).toHaveAccessibleName('Notebook save Saved');

  const stored = () => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const note = await (await root.getDirectoryHandle('Papers')).getDirectoryHandle('mixed-pages');
    const pages = await note.getDirectoryHandle('pages');
    const assets = await note.getDirectoryHandle('assets');
    const manifest: { pages: { file: string }[] } = JSON.parse(
      await (await (await note.getFileHandle('notebook.json')).getFile()).text(),
    );
    const result = [];
    for (const [index, entry] of manifest.pages.entries()) {
      const number = index + 1;
      const file = await (await pages.getFileHandle(entry.file.replace('pages/', ''))).getFile();
      const svg = new DOMParser().parseFromString(await file.text(), 'image/svg+xml');
      if (svg.querySelector('parsererror')) throw new Error(`Page ${number} is not valid SVG`);
      const image = svg.querySelector('g#background image');
      if (!image) throw new Error(`Page ${number} lost its PDF background`);
      const name = image.getAttribute('href')?.split('/').at(-1);
      if (!name) throw new Error(`Page ${number} has no background asset`);
      const bitmap = await createImageBitmap(await (await assets.getFileHandle(name)).getFile());
      const pngWidth = bitmap.width;
      bitmap.close();
      result.push({
        size: svg.documentElement.getAttribute('viewBox')?.split(' ').slice(2).map(Number),
        pngWidth,
        strokes: svg.querySelectorAll('path[id^="s-"]').length,
      });
    }
    return result;
  });
  expect(await stored()).toEqual([
    { size: [595, 842], pngWidth: 4128, strokes: 0 },
    { size: [960, 540], pngWidth: 4128, strokes: 1 },
    { size: [595, 842], pngWidth: 4128, strokes: 0 },
  ]);

  await page.getByRole('button', { name: 'More', exact: true }).click();
  await page.getByRole('button', { name: 'Export PDF', exact: true }).click();
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  const exported = info.outputPath('mixed-export.pdf');
  await (await download).saveAs(exported);
  const infoText = execFileSync('pdfinfo', ['-f', '1', '-l', '3', exported], { encoding: 'utf8' });
  expect(infoText).toMatch(/Pages:\s+3/);
  expect([...infoText.matchAll(/Page\s+\d size:\s+(\d+) x (\d+) pts/g)].map(([, width, height]) => [Number(width), Number(height)]))
    .toEqual([[595, 842], [960, 540], [595, 842]]);
  expect(execFileSync('qpdf', ['--check', exported], { encoding: 'utf8' })).toContain('No syntax or stream encoding errors found');
  const pageObjects = execFileSync('qpdf', ['--show-pages', exported], { encoding: 'utf8' });
  const contentIds = [...pageObjects.matchAll(/content:\s*\n\s*(\d+) 0 R/g)].map(([, id]) => id);
  expect(contentIds).toHaveLength(3);
  const streams = contentIds.map(id => execFileSync('qpdf', [`--show-object=${id}`, '--filtered-stream-data', exported], { encoding: 'utf8' }));
  expect(streams[0]).not.toMatch(/^[-.\d ]+ m$/m);
  expect(streams[1], 'page two carries vector ink over its background').toMatch(/^[-.\d ]+ m$/m);
  expect(streams[2]).not.toMatch(/^[-.\d ]+ m$/m);

  for (const [number, width, height, bar] of [[1, 595, 842, 200], [2, 960, 540, 400], [3, 595, 842, 300]]) {
    const prefix = info.outputPath(`rendered-${number}`);
    execFileSync('pdftoppm', ['-r', '72', '-png', '-f', String(number), '-l', String(number), '-singlefile', exported, prefix]);
    const png = await readFile(`${prefix}.png`);
    const rendered = await page.evaluate(async bytes => {
      const bitmap = await createImageBitmap(new Blob([new Uint8Array(bytes)], { type: 'image/png' }));
      const canvas = document.createElement('canvas');
      canvas.width = bitmap.width;
      canvas.height = bitmap.height;
      const context = canvas.getContext('2d')!;
      context.drawImage(bitmap, 0, 0);
      const pixels = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
      let longest = 0;
      for (let y = 0; y < bitmap.height * .4; y++) {
        let run = 0;
        for (let x = 0; x < bitmap.width; x++) {
          const i = (y * bitmap.width + x) * 4;
          run = pixels[i] + pixels[i + 1] + pixels[i + 2] < 180 ? run + 1 : 0;
          longest = Math.max(longest, run);
        }
      }
      const size = [bitmap.width, bitmap.height];
      bitmap.close();
      return { size, longest };
    }, [...png]);
    expect(rendered, `independent PDF render of page ${number}`).toEqual({ size: [width, height], longest: bar });
  }

  await page.reload();
  await page.getByRole('button', { name: /^Open Papers/ }).click();
  await page.getByRole('button', { name: /^Open mixed-pages/ }).click();
  await canvas.waitFor();
  expect(await stored()).toEqual([
    { size: [595, 842], pngWidth: 4128, strokes: 0 },
    { size: [960, 540], pngWidth: 4128, strokes: 1 },
    { size: [595, 842], pngWidth: 4128, strokes: 0 },
  ]);
});
