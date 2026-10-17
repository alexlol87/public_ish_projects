import { defineConfig } from "vitest/config";

export default defineConfig({
  root: "ui",
  clearScreen: false,
  server: { port: 1420, strictPort: true, watch: { ignored: ["**/src-tauri/**"] } },
  build: { outDir: "../dist", emptyOutDir: true, target: "es2022" },
  test: { include: ["src/**/*.test.ts"] },
});
