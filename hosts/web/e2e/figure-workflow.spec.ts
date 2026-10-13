import { test, expect } from '@playwright/test';
import { createTestNotebook, enterText, penStroke, save } from './workflow-actions.ts';

test('a captured doodle opens the visual editor and keeps its ink and TikZ source after reopen', async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto('?root=opfs');
  await createTestNotebook(page, 'Diagrams');
  await page.getByRole('button', { name: 'New note', exact: true }).click();
  await enterText(page.getByRole('textbox', { name: 'Title', exact: true }), 'Commutative square');
  await page.getByRole('button', { name: 'Create', exact: true }).click();

  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  const box = (await canvas.boundingBox())!;
  const cdp = await page.context().newCDPSession(page);
  await page.getByRole('button', { name: 'Drawing mode', exact: true }).click();
  await penStroke(cdp, [
    { x: box.x + 170, y: box.y + 180 },
    { x: box.x + 220, y: box.y + 180 },
    { x: box.x + 270, y: box.y + 180 },
  ], .8);
  await page.getByRole('button', { name: 'Complete drawing', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Save and close', exact: true })).toBeVisible();
  const editor = page.frameLocator('iframe[title="TikZ figure editor"]');
  const drawing = editor.frameLocator('iframe[title="TikZ visual editor"]');
  await expect(editor.getByRole('button', { name: 'Draw', exact: true })).toBeVisible();
  await expect(drawing.locator('[data-canvas-viewport="true"]')).toBeVisible();
  await expect.poll(() => drawing.locator('[data-source-id]').count()).toBeGreaterThan(0);
  await editor.getByRole('button', { name: 'Draw', exact: true }).click();
  const drawingBox = (await drawing.locator('[data-canvas-viewport="true"]').boundingBox())!;
  await page.mouse.move(drawingBox.x + drawingBox.width * .4, drawingBox.y + drawingBox.height * .45);
  await page.mouse.down();
  await page.mouse.move(drawingBox.x + drawingBox.width * .6, drawingBox.y + drawingBox.height * .55, { steps: 12 });
  await page.mouse.up();
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.getByRole('button', { name: 'Copy TikZ', exact: true }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toContain('workbench-ink:');
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  await page.getByRole('button', { name: 'Save and close', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Save and close', exact: true })).toHaveCount(0);
  await save(page);
  await expect(page.getByRole('status', { name: /^Notebook save/ })).toHaveAccessibleName('Notebook save Saved');

  const stored = async () => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const note = await (await root.getDirectoryHandle('Diagrams')).getDirectoryHandle('Commutative square');
    const svg = await (await (await note.getDirectoryHandle('pages')).getFileHandle('0001.svg')).getFile().then(file => file.text());
    const figure = /<g id="(f-[^"]+)" class="mn-figure"/.exec(svg)?.[1];
    if (!figure) throw new Error('No figure in the saved page');
    const original = await (await (await note.getDirectoryHandle('assets')).getFileHandle(`${figure}.tikz`)).getFile().then(file => file.text());
    const draftHref = new RegExp(`<g id="${figure}"[^>]*mn:draft="([^"]+)"`).exec(svg)?.[1];
    if (!draftHref) throw new Error('The saved figure does not link its edited draft');
    const draftName = draftHref.split('/').at(-1)!;
    const tikz = await (await (await note.getDirectoryHandle('assets')).getFileHandle(draftName)).getFile().then(file => file.text());
    return { figure, svg, original, draftName, tikz };
  });
  const before = await stored();
  expect(before.svg).toContain('<path id="s-');
  expect(before.original).toContain('\\begin{tikzpicture}');
  expect(before.tikz).toContain('\\begin{tikzpicture}');
  expect(before.tikz).toContain('workbench-ink:');
  expect(before.tikz).toBe(copied);

  await page.reload();
  await page.getByRole('button', { name: /^Open Diagrams/ }).click();
  await page.getByRole('button', { name: /^Open Commutative square/ }).click();
  await canvas.waitFor();
  const after = await stored();
  expect(after).toEqual(before);
});
