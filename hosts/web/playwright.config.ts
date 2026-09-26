import { defineConfig, devices } from "@playwright/test";

// Against the nginx deployment (just web-deploy). MATH_NOTES_URL overrides it.
// Chromium runs every spec; Firefox and WebKit run the storage specs that
// replace the File System Access API there (#27).
const otherBrowsers = /(webdav|published)\.spec\.ts/;

export default defineConfig({
  testDir: "e2e",
  use: { baseURL: process.env.MATH_NOTES_URL ?? "http://localhost/math-notes/" },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] }, testIgnore: /webdav\.spec\.ts/ },
    // Headless Firefox on a GPU-less runner finds no GL driver; CI runs it
    // headed under Xvfb, where Mesa supplies GL (TRAPS.md).
    { name: "firefox", use: { ...devices["Desktop Firefox"], headless: !process.env.CI }, testMatch: otherBrowsers },
    { name: "webkit", use: { ...devices["Desktop Safari"] }, testMatch: otherBrowsers },
  ],
});
