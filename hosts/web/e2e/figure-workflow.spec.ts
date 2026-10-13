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
  await expect(page.frameLocator('iframe[title="TikZ figure editor"]').getByRole('img', { name: 'TikZ SVG preview' })).toBeVisible();
  await page.context().grantPermissions(['clipboard-read']);
  await page.getByRole('button', { name: 'Copy TikZ', exact: true }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toContain('\\begin{tikzpicture}');
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
    const tikz = await (await (await note.getDirectoryHandle('assets')).getFileHandle(`${figure}.tikz`)).getFile().then(file => file.text());
    return { figure, svg, tikz };
  });
  const before = await stored();
  expect(before.svg).toContain('<path id="s-');
  expect(before.tikz).toContain('\\begin{tikzpicture}');

  await page.reload();
  await page.getByRole('button', { name: /^Open Diagrams/ }).click();
  await page.getByRole('button', { name: /^Open Commutative square/ }).click();
  await canvas.waitFor();
  const after = await stored();
  expect(after).toEqual(before);
});
