import { generateSW } from "workbox-build";

// Workbox owns revisioned precaching and the worker lifecycle:
// https://developer.chrome.com/docs/workbox/modules/workbox-build
const result = await generateSW({
  globDirectory: "flutter/build/web",
  globPatterns: ["**/*.{js,wasm,html,svg,png,ttf,otf,json,bin,frag,data}"],
  globIgnores: ["sw.js", "workbox-*.js", "flutter_service_worker.js"],
  maximumFileSizeToCacheInBytes: 512 * 1024 * 1024,
  swDest: "flutter/build/web/sw.js",
  navigateFallback: "index.html",
  cleanupOutdatedCaches: true,
  clientsClaim: true,
  skipWaiting: false,
});
if (result.warnings.length) throw new Error(result.warnings.join("\n"));
