import path from 'node:path';
import { defineConfig } from 'vitest/config';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers';

// Everything runs inside workerd (miniflare): D1, Durable Objects, alarms.
// No network, no Cloudflare account, no secrets: the test secret below is a
// throwaway literal and the OpenAI key is deliberately absent.
export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, 'migrations'));
  return {
    plugins: [
      cloudflareTest({
        main: './src/index.ts',
        wrangler: { configPath: './wrangler.toml', environment: 'dev' },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            PARENT_TOKEN_SECRET: 'test-only-parent-token-secret-not-for-deployment',
            DEV_MODE: '1',
            RATE_LIMIT_IP_PER_MINUTE: '100000',
          },
        },
      }),
    ],
    test: {
      include: ['test/**/*.test.ts'],
      setupFiles: ['./test/setup.ts'],
      onConsoleLog(log: string) {
        if (log.startsWith('[cloud]') || log.startsWith('[tutor')) return false;
        return undefined;
      },
    },
  };
});
