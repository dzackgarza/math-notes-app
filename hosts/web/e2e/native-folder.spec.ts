import { test, expect } from "./native-desktop.ts";
import { mkdir, rename } from "node:fs/promises";
import { join } from "node:path";

test.use({ trace: "on" });

test("opens a genuinely selected folder without waiting for background browser startup", async ({ desktop }) => {
  test.setTimeout(90_000);
  await desktop.chooseFolder();
  await expect(desktop.page.getByRole("button", { name: "New notebook", exact: true })).toBeVisible({ timeout: 10_000 });
  // An external writer can change the directory after the first library
  // read but before Chrome attaches the watcher. No second change or manual
  // refresh should be necessary to discover it.
  await mkdir(join(desktop.notes, "External research"));
  await expect(desktop.page.getByRole("button", { name: /^Open External research/ })).toBeVisible({ timeout: 65_000 });
  await rename(join(desktop.notes, "External research"), join(desktop.notes, "Renamed research"));
  await expect(desktop.page.getByRole("button", { name: /^Open Renamed research/ })).toBeVisible();
  await expect(desktop.page.getByRole("button", { name: /^Open External research/ })).toHaveCount(0);
});

