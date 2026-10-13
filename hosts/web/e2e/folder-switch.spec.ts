import { test, expect } from "./native-desktop.ts";
import { enterText } from "./workflow-actions.ts";
import { mkdir, readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

test("keeps queued creation and metadata in their originating folder while switching", async ({ desktop }, info) => {
  test.setTimeout(360_000);
  let page = desktop.page;
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await desktop.chooseFolder();
  await button("New notebook").click({ timeout: 90_000 });
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Folder A work");
  await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Belongs only to A");

  // Another same-origin tab holds the real production filesystem lock. This
  // introduces real contention without replacing a browser or host API.
  const other = await page.context().newPage();
  await other.goto(new URL("version.json", page.url()).href);
  const held = other.evaluate(() => navigator.locks.request("math-notes-files", async () => {
    document.title = "Folder lock held";
    await new Promise<void>(resolve => window.addEventListener("release-folder-lock", () => resolve(), { once: true }));
  }));
  try {
    await expect(other).toHaveTitle("Folder lock held");
    await page.bringToFront();
    await button("Create").click();
    await button("New tag").click();
    await enterText(page.getByRole("textbox", { name: "Tag name", exact: true }), "A-only tag");
    await button("Add tag").click();
    const second = info.outputPath("folder-b");
    await mkdir(join(second, "B existing"), { recursive: true });
    await button("Settings").click();
    await desktop.chooseFolder(second);
    await other.evaluate(() => window.dispatchEvent(new Event("release-folder-lock")));
    await held;
    await expect(page.getByRole("button", { name: /^Open B existing/ })).toBeVisible({ timeout: 90_000 });
    await expect(page.getByRole("button", { name: /^Open Folder A work/ })).toHaveCount(0);
    expect(await readdir(second)).toEqual(["B existing"]);
    const metadata = JSON.parse(await readFile(join(desktop.notes, ".library.json"), "utf8"));
    expect(metadata.folders["Folder A work"].description).toBe("Belongs only to A");
    expect(metadata.tags.map((tag: { name: string }) => tag.name)).toContain("A-only tag");
    expect(await readdir(desktop.notes)).toContain("Folder A work");
    await button("New notebook").click();
    await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "B subsequent work");
    await button("Create").click();
    await expect(page.getByRole("heading", { name: "B subsequent work", exact: true })).toBeVisible();
    expect(await readdir(desktop.notes)).not.toContain("B subsequent work");
    expect(await readdir(second)).toContain("B subsequent work");
  } finally {
    await other.evaluate(() => window.dispatchEvent(new Event("release-folder-lock")));
    await held;
    await other.close();
  }

  page = await desktop.restart();
  await button("Reconnect folder").click();
  await desktop.allow("Allow this time");
  await expect(page.getByRole("button", { name: /^Open B existing/ })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByRole("button", { name: /^Open Folder A work/ })).toHaveCount(0);
  await page.getByRole("button", { name: /^Open B subsequent work/ }).click();
  await expect(page.getByRole("heading", { name: "B subsequent work", exact: true })).toBeVisible();
  await button("Library").click();
  await button("Settings").click();
  // Chrome already granted this folder earlier in the same profile.
  await desktop.chooseFolder(desktop.notes, false);
  await expect(page.getByRole("button", { name: /^Open Folder A work/ })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByRole("button", { name: /^Open B subsequent work/ })).toHaveCount(0);
  await expect(page.getByText("Belongs only to A", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: /^Open Folder A work/ }).click();
  await expect(page.getByRole("heading", { name: "Folder A work", exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("reopened-originating-folder.png") });
});
