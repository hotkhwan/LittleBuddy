import { defineConfig } from 'vitest/config';

// Pure domain tests do not need workerd. Keeping them in a Node pool makes
// subscription and licensing policy testable in restricted CI sandboxes.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/commerce.test.ts', 'test/licensing.test.ts'],
  },
});
