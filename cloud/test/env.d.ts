/// <reference types="@cloudflare/vitest-pool-workers/types" />
import type { Env } from '../src/env';

declare global {
  namespace Cloudflare {
    interface Env extends Omit<import('../src/env').Env, 'TEST_MIGRATIONS'> {
      TEST_MIGRATIONS: import('cloudflare:test').D1Migration[];
    }
  }
}

export type { Env };
