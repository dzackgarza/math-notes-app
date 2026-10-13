import { defineConfig, devices } from "@playwright/test";

// Against the nginx deployment (just web-fetch). MATH_NOTES_URL overrides it.
// Each workflow makes its own notes in its own browser context. CI runs the
// workflows in shards. Native desktop workflows each launch Chrome,
// Xvfb, Openbox and a file chooser, so one worker per shard keeps their OS
// input and startup timing independent of another workflow on that runner.
export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  workers: process.env.CI ? 1 : undefined,
  reporter: "list",
  use: {
    baseURL: process.env.MATH_NOTES_URL ?? "http://localhost/math-notes/",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
