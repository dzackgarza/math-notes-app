import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  worker: { format: "es" },
  build: {
    outDir: "flutter/build/bridge",
    rolldownOptions: {
      input: "src/flutter.ts",
      output: { entryFileNames: "host.js" },
    },
  },
});
