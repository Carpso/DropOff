import { defineConfig } from 'vitest/config';

// Integration scaffold - wire with @cloudflare/vitest-pool-workers when available.
// Existing unit tests keep using default vitest behavior.
export default defineConfig({
  test: {
    include: ['test/integration/**/*.test.ts'],
  },
});
