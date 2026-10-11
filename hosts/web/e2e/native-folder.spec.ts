import { test, expect } from "./native-desktop.ts";

test.use({ trace: "on" });

test("opens a genuinely selected folder without waiting for background browser startup", async ({ desktop }) => {
  test.setTimeout(90_000);
  await desktop.chooseFolder();
  await expect(desktop.page.getByRole("button", { name: "New notebook", exact: true })).toBeVisible({ timeout: 10_000 });
});

