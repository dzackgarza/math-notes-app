import { defineConfig, devices } from "@playwright/test";

// Against the nginx deployment (just web-deploy). MATH_NOTES_URL overrides it.
export default defineConfig({
  testDir: "e2e",
  use: {
    baseURL: process.env.MATH_NOTES_URL ?? "http://localhost/math-notes/",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
