import { expect } from "@playwright/test";
import { test, createTestNotebook, enterText } from "./support.ts";

test("the library tree opens notes and offers explicit creation targets", async ({ page }) => {
  test.setTimeout(180_000);
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
  await button("Create options").click();
  await button("New note in Test Notebook").click();
  await expect(page.getByText("New note in Test Notebook", { exact: true })).toBeVisible();
});
