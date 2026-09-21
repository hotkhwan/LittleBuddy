// Worker entry. Exposes the Durable Object classes and the fetch + scheduled handlers.
import { createApp } from './app';
import { loadConfig, type Env } from './env';
import { purgeExpired } from './db/retention';

export { TutorSessionDO } from './do/tutor_session_do';
export { QuotaDO } from './do/quota_do';

const app = createApp();

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return app.fetch(request, env, ctx);
  },
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    const config = loadConfig(env);
    ctx.waitUntil(purgeExpired(env.DB, Date.now(), config.retentionDays).then((counts) => {
      console.log(`[cloud] retention purge: sessions=${counts.sessions} usage=${counts.usageEvents} quota=${counts.dailyQuota} idempotency=${counts.idempotency}`);
    }));
  },
} satisfies ExportedHandler<Env>;
