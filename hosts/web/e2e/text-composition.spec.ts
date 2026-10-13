import { test, expect } from '@playwright/test';
import { createTestNotebook, enterText, focusText, save } from './workflow-actions.ts';

test('text composition keeps Devanagari and Arabic source through save and reopen', async ({ page }) => {
  test.setTimeout(180_000);
  await page.goto('?root=opfs');
  await createTestNotebook(page, 'Languages');
  await page.getByRole('button', { name: 'New note', exact: true }).click();
  await enterText(page.getByRole('textbox', { name: 'Title', exact: true }), 'Composition');
  await page.getByRole('button', { name: 'Create', exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  await page.getByRole('button', { name: 'Text', exact: true }).click();
  await expect(page.getByText('Insert text', { exact: true })).toBeVisible();
  const field = page.getByRole('textbox', { name: 'Text', exact: true });
  await expect(field).toBeVisible();
  await focusText(field);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.imeSetComposition', { text: 'नम', selectionStart: 2, selectionEnd: 2 });
  await expect(field).toHaveValue('नम');
  await cdp.send('Input.imeSetComposition', { text: 'नमस्ते', selectionStart: 6, selectionEnd: 6 });
  await cdp.send('Input.insertText', { text: 'नमस्ते' });
  await expect(field).toHaveValue('नमस्ते');
  await cdp.send('Input.insertText', { text: '\nنظرية الجبر' });
  await expect(field).toHaveValue('नमस्ते\nنظرية الجبر');
  await page.getByRole('button', { name: 'Done', exact: true }).click();
  await page.getByRole('button', { name: 'Clear selection', exact: true }).click();
  await save(page);
  await expect(page.getByRole('status', { name: /^Notebook save/ })).toHaveAccessibleName('Notebook save Saved');

  const authored = async () => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const note = await (await root.getDirectoryHandle('Languages')).getDirectoryHandle('Composition');
    const manifest: { pages: { file: string }[] } = JSON.parse(
      await (await (await note.getFileHandle('notebook.json')).getFile()).text(),
    );
    const file = await (await note.getDirectoryHandle('pages')).getFileHandle(manifest.pages[0].file.replace('pages/', ''));
    const svg = new DOMParser().parseFromString(await (await file.getFile()).text(), 'image/svg+xml');
    if (svg.querySelector('parsererror')) throw new Error('Saved text page is not valid SVG');
    return Array.from(svg.querySelectorAll('text tspan'), span => span.textContent);
  });
  expect(await authored()).toEqual(['नमस्ते', 'نظرية الجبر']);

  await page.reload();
  await page.getByRole('button', { name: /^Open Languages/ }).click();
  await page.getByRole('button', { name: /^Open Composition/ }).click();
  await canvas.waitFor();
  expect(await authored()).toEqual(['नमस्ते', 'نظرية الجبر']);
});
