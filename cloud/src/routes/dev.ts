// DEV_MODE only. Mounted only when DEV_MODE=1 (404 otherwise, like the prototype).
import { Hono } from 'hono';
import { ENTITLEMENTS, type Entitlement, type Env } from '../env';
import { requireAuth, type Vars } from '../auth/context';
import { errors } from '../errors';
import { ID_RE, str } from '../util/validate';
import { setEntitlement } from '../db/entitlements';
import { purgeExpired } from '../db/retention';
import { monthlySpendMicro } from '../db/usage';
import { LESSONS } from '../tutor/lessons';
import { ASSET_ALLOWLIST } from '../tutor/content';
import { openAiFactoryWired } from '../tutor/provider_registry';

export const devRoutes = new Hono<{ Bindings: Env; Variables: Vars }>();

devRoutes.post('/dev/entitlements', async (c) => {
  const auth = requireAuth(c);
  const config = c.get('config');
  const now = c.get('now');
  const body = c.get('body');
  const entitlement = str(body, 'entitlement', { required: true, max: 20 }) as Entitlement;
  if (!ENTITLEMENTS.includes(entitlement)) throw errors.badRequest('entitlement must be free or family_club');
  const productId = str(body, 'productId', { max: 80 }) || config.familyClubProductIds[0];
  const days = Number((body as Record<string, unknown>)?.days ?? 30);
  await setEntitlement(c.env.DB, { parentId: auth.parentId, productId, source: 'dev', status: entitlement === 'family_club' ? 'active' : 'revoked', periodEnd: Number.isFinite(days) && days > 0 ? now + days * 86_400_000 : null, now });
  return c.json({ parentId: auth.parentId, entitlement, productId, source: 'dev' });
});

devRoutes.post('/dev/parent-approval', async (c) => {
  const auth = requireAuth(c);
  const config = c.get('config');
  const now = c.get('now');
  const clientId = str(c.get('body'), 'clientId', { required: true, max: 128, re: ID_RE });
  const token = await c.get('tokens').mintApproval({ clientId, parentId: auth.parentId }, now, config.parentTokenTtlSeconds);
  return c.json({ clientId, parentApprovalToken: token, devToken: 'dev-parent-approval' });
});

devRoutes.post('/dev/retention/purge', async (c) => {
  requireAuth(c);
  return c.json(await purgeExpired(c.env.DB, c.get('now'), c.get('config').retentionDays));
});

devRoutes.get('/dev/spend', async (c) => {
  requireAuth(c);
  const config = c.get('config');
  const spend = await monthlySpendMicro(c.env.DB, c.get('now'));
  return c.json({ ...spend, spentUsd: spend.spentUsdMicro / 1e6, monthlyBudgetUsd: config.monthlyBudgetUsd, provider: config.providerName, openAiFactoryWired: openAiFactoryWired(), lessons: [...LESSONS.keys()], allowlistSource: ASSET_ALLOWLIST.source });
});
