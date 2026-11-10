import { defineConfig } from "vitest/config";

// Test files share one database: run them one at a time.
export default defineConfig({ test: { fileParallelism: false } });
