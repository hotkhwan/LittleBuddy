import { applyD1Migrations, env } from 'cloudflare:test';

// Runs once per test file; per-test writes are rolled back by isolatedStorage.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
