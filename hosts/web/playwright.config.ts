import { defineConfig, devices } from "@playwright/test";

// Against the nginx deployment (just web-fetch). MATH_NOTES_URL overrides it.
// Each workflow makes its own notes in its own browser context, so the
// workflows of the one spec file run in parallel; CI runs them in shards.
export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  workers: process.env.CI ? 2 : undefined,
  reporter: "list",
  use: {
    baseURL: process.env.MATH_NOTES_URL ?? "http://localhost/math-notes/",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
