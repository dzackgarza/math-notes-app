import { expect } from "@playwright/test";
import { test, createTestNotebook, enterText } from "./support.ts";

test("the library tree opens notes and offers explicit creation targets", async ({ page }) => {
  test.setTimeout(90_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await button("Back to library").click();

  await expect(button("Untagged")).toBeVisible();
  await button("Test Notebook").click();
  await expect(page.getByRole("heading", { name: "Test Notebook", exact: true })).toBeVisible();
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Tree note");
  await button("Create").click();
  await expect(page.getByRole("heading", { name: "Tree note", exact: true })).toBeVisible();
  await button("Library").click();
  await expect(button("Tree note")).toBeVisible();
  await button("Tree note").click();
  await expect(page.getByRole("heading", { name: "Tree note", exact: true })).toBeVisible();

  await button("Library").click();
  await button("Tree note actions").click();
  await button("Pin note").click();
  await button("Pinned").click();
  await expect(button("Test Notebook")).toHaveCount(2);
  await button("Test Notebook").last().click();
  await expect(button("Tree note")).toHaveCount(2);
  await button("Tree note actions").click();
  await button("Move to trash").click();
  await button("Trash").click();
  await expect(button("Tree note actions")).toBeVisible({ timeout: 30_000 });
  await expect(button("Tree note")).toHaveCount(1);
  await button("Create options").click();
  await button("New note in Test Notebook").click();
  await expect(page.getByText("New note in Test Notebook", { exact: true })).toBeVisible();
  await button("Cancel").click();

  await button("New notebook").click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Other notebook");
  await button("Create").click();
  await expect(page.getByRole("heading", { name: "Other notebook", exact: true })).toBeVisible();
  await button("Back to library").click();
  await button("Create options").click();
  await button("New note in…").click();
  await expect(page.getByText("Choose notebook", { exact: true })).toBeVisible();
  await button("Test Notebook").last().click();
  await expect(page.getByText("New note in Test Notebook", { exact: true })).toBeVisible();
});
