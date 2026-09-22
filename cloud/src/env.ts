// Bindings and configuration. No secret has a default; every number is
// parsed defensively so a typo in wrangler.toml can never mean "unlimited".
import type { TutorSessionDO } from './do/tutor_session_do';
import type { QuotaDO } from './do/quota_do';

export interface Env {
  DB: D1Database;
  AI: Ai;
  AI_SEARCH: AiSearchNamespace;
  TUTOR_SESSION: DurableObjectNamespace<TutorSessionDO>;
  QUOTA: DurableObjectNamespace<QuotaDO>;
  // vars (wrangler.toml)
  APP_NAME?: string;
  DEV_MODE?: string;
  BILLING_ENABLED?: string;
  PRODUCTION_ENABLED?: string;
  LIVE_CHILD_AUDIO_ENABLED?: string;
  FREE_DAILY_SECONDS?: string;
  FAMILY_CLUB_DAILY_SECONDS?: string;
  FREE_DAILY_TURNS?: string;
  FAMILY_CLUB_DAILY_TURNS?: string;
  TUTOR_TURN_CAP_SECONDS?: string;
  SESSION_IDLE_SECONDS?: string;
  REALTIME_GRACE_SECONDS?: string;
  RETENTION_DAYS?: string;
  MONTHLY_BUDGET_USD?: string;
  MAX_BODY_BYTES?: string;
  RATE_LIMIT_IP_PER_MINUTE?: string;
  RATE_LIMIT_SESSION_TURNS_PER_MINUTE?: string;
  PARENT_TOKEN_TTL_SECONDS?: string;
  FAMILY_CLUB_PRODUCT_IDS?: string;
  FAMILY_CLUB_PRICE_CURRENCY?: string;
  FAMILY_CLUB_PRICE_MONTHLY?: string;
  FAMILY_CLUB_PRICE_STATUS?: string;
  CONSENT_VERSION?: string;
  TUTOR_PROVIDER?: string;
  TUTOR_MODEL?: string;
  REALTIME_MODEL?: string;
  REALTIME_VOICE?: string;
  REALTIME_TURN_DETECTION?: string;
  REALTIME_WS_URL?: string;
  PROVIDER_TIMEOUT_MS?: string;
  PLAN_POLICY_JSON?: string;
  STORE_PRODUCT_MAP_JSON?: string;
  STANDARD_PROVIDER?: string;
  PREMIUM_LIVE_PROVIDER?: string;
  PROVIDER_BUDGET_CENTS_MONTHLY?: string;
  PROVIDER_BUDGET_CENTS_DAILY?: string;
  STANDARD_PRIMARY_MODEL?: string;
  STANDARD_FALLBACK_MODEL?: string;
  COMPLEX_REASONING_MODEL?: string;
  AI_SEARCH_INSTANCE?: string;
  // secrets (.dev.vars locally, `wrangler secret put` remotely)
  PARENT_TOKEN_SECRET?: string;
  OPENAI_API_KEY?: string;
  OPENAI_BASE_URL?: string;
  DEEPSEEK_API_KEY?: string;
  DEEPSEEK_BASE_URL?: string;
  GEMINI_API_KEY?: string;
  APPLE_ISSUER_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
  GOOGLE_PACKAGE_NAME?: string;
  GOOGLE_SERVICE_ACCOUNT_JSON?: string;
  GOOGLE_RTDN_TOKEN?: string;
  // tests only
  TEST_MIGRATIONS?: unknown;
}

export const DEFAULT_MONTHLY_BUDGET_USD = 25;
export const DEV_PARENT_APPROVAL_LITERAL = 'dev-parent-approval';
export const DEV_PARENT_ID = 'dev-parent';

export type Entitlement = 'free' | 'family_club';
export const ENTITLEMENTS: readonly Entitlement[] = ['free', 'family_club'];

export interface Config {
  devMode: boolean;
  appName: string;
  billingEnabled: boolean;
  freeDailySeconds: number;
  familyClubDailySeconds: number;
  freeDailyTurns: number;
  familyClubDailyTurns: number;
  turnCapSeconds: number;
  sessionIdleSeconds: number;
  realtimeGraceSeconds: number;
  retentionDays: number;
  monthlyBudgetUsd: number;
  maxBodyBytes: number;
  ipPerMinute: number;
  sessionTurnsPerMinute: number;
  parentTokenTtlSeconds: number;
  familyClubProductIds: string[];
  priceHint: { currency: string; monthly: number; status: string };
  consentVersion: number;
  providerName: 'mock' | 'faulty' | 'workers_ai' | 'openai';
  model: string;
  standardPrimaryModel: string;
  standardFallbackModel: string;
  complexReasoningModel: string;
  realtimeModel: string;
  realtimeVoice: string;
  realtimeTurnDetection: 'semantic_vad' | 'server_vad';
  realtimeWsUrl: string;
  providerTimeoutMs: number;
  hasOpenAiKey: boolean;
  productionEnabled: boolean;
  liveChildAudioEnabled: boolean;
  standardProvider: 'workers_ai' | 'openai' | 'deepseek' | 'mock';
  premiumLiveProvider: 'gemini' | 'mock';
  providerBudgetCentsMonthly: number;
  providerBudgetCentsDaily: number;
  planPolicies: Record<Plan, PlanPolicy>;
  storeProductMap: Record<string, { plan: Plan; platform: 'apple' | 'google' }>;
}

export type Plan = 'FREE' | 'FAMILY' | 'PREMIUM' | 'PREMIUM_PLUS';
export interface PlanPolicy {
  features: string[];
  standardDailySeconds: number;
  standardMonthlyTokens: number;
  liveMonthlySeconds: number;
  liveSessionMaxSeconds: number;
  freeTrialLiveSecondsDaily: number;
  freeTrialDays: number;
  childProfileLimit: number;
  liveRollover: boolean;
}

const DEFAULT_PLAN_POLICIES: Record<Plan, PlanPolicy> = {
  FREE: { features: ['core_game', 'local_lessons', 'standard_ai_trial', 'premium_live_trial'], standardDailySeconds: 300, standardMonthlyTokens: 20_000, liveMonthlySeconds: 0, liveSessionMaxSeconds: 300, freeTrialLiveSecondsDaily: 300, freeTrialDays: 7, childProfileLimit: 1, liveRollover: false },
  FAMILY: { features: ['core_game', 'local_lessons', 'standard_ai', 'basic_progress'], standardDailySeconds: 3600, standardMonthlyTokens: 500_000, liveMonthlySeconds: 0, liveSessionMaxSeconds: 900, freeTrialLiveSecondsDaily: 0, freeTrialDays: 0, childProfileLimit: 3, liveRollover: false },
  PREMIUM: { features: ['core_game', 'local_lessons', 'standard_ai', 'premium_live', 'progress_insights', 'personalized_learning'], standardDailySeconds: 3600, standardMonthlyTokens: 800_000, liveMonthlySeconds: 18_000, liveSessionMaxSeconds: 1800, freeTrialLiveSecondsDaily: 0, freeTrialDays: 0, childProfileLimit: 3, liveRollover: false },
  PREMIUM_PLUS: { features: ['core_game', 'local_lessons', 'standard_ai', 'premium_live', 'advanced_reports', 'skill_recommendations', 'advanced_personalization', 'early_access_content'], standardDailySeconds: 3600, standardMonthlyTokens: 1_200_000, liveMonthlySeconds: 36_000, liveSessionMaxSeconds: 1800, freeTrialLiveSecondsDaily: 0, freeTrialDays: 0, childProfileLimit: 3, liveRollover: false },
};

function jsonObject(raw: string | undefined): Record<string, unknown> {
  if (!raw) return {};
  try { const parsed = JSON.parse(raw); return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {}; } catch { return {}; }
}

function planPolicies(raw: string | undefined): Record<Plan, PlanPolicy> {
  const source = jsonObject(raw);
  const out = structuredClone(DEFAULT_PLAN_POLICIES);
  for (const plan of Object.keys(out) as Plan[]) {
    const row = source[plan];
    if (!row || typeof row !== 'object' || Array.isArray(row)) continue;
    const input = row as Record<string, unknown>;
    for (const key of ['standardDailySeconds', 'standardMonthlyTokens', 'liveMonthlySeconds', 'liveSessionMaxSeconds', 'freeTrialLiveSecondsDaily', 'freeTrialDays', 'childProfileLimit'] as const) {
      const value = Number(input[key]);
      if (Number.isFinite(value) && value >= 0) out[plan][key] = Math.floor(value);
    }
    if (Array.isArray(input.features) && input.features.every((v) => typeof v === 'string')) out[plan].features = [...new Set(input.features as string[])].slice(0, 64);
    if (typeof input.liveRollover === 'boolean') out[plan].liveRollover = input.liveRollover;
  }
  return out;
}

function storeMap(raw: string | undefined): Config['storeProductMap'] {
  const source = jsonObject(raw); const out: Config['storeProductMap'] = {};
  for (const [id, value] of Object.entries(source)) {
    if (!id || !value || typeof value !== 'object' || Array.isArray(value)) continue;
    const row = value as Record<string, unknown>;
    if (['FREE', 'FAMILY', 'PREMIUM', 'PREMIUM_PLUS'].includes(String(row.plan)) && (row.platform === 'apple' || row.platform === 'google')) out[id] = { plan: row.plan as Plan, platform: row.platform };
  }
  return out;
}

function num(env: Env, key: keyof Env, fallback: number): number {
  const raw = env[key];
  if (raw === undefined || raw === null || raw === '') return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}

function positiveOr(n: number, fallback: number): number {
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/** Pure: no I/O. Safe to call per request. */
export function loadConfig(env: Env): Config {
  const devMode = env.DEV_MODE === '1' || env.DEV_MODE === 'true';
  const hasOpenAiKey = typeof env.OPENAI_API_KEY === 'string' && env.OPENAI_API_KEY.length > 0;
  const requested = (env.TUTOR_PROVIDER || '').toLowerCase();
  // `faulty` exists for chaos tests of the fallback path and is honoured in DEV_MODE only.
  const providerName: Config['providerName'] = requested === 'faulty' && devMode ? 'faulty' : requested === 'workers_ai' ? 'workers_ai' : hasOpenAiKey && requested !== 'mock' ? 'openai' : 'mock';
  return {
    devMode,
    appName: env.APP_NAME || 'Little Days',
    billingEnabled: env.BILLING_ENABLED === 'true' || env.BILLING_ENABLED === '1',
    productionEnabled: env.PRODUCTION_ENABLED === 'true' || env.PRODUCTION_ENABLED === '1',
    liveChildAudioEnabled: env.LIVE_CHILD_AUDIO_ENABLED === 'true' || env.LIVE_CHILD_AUDIO_ENABLED === '1',
    freeDailySeconds: Math.max(0, Math.min(num(env, 'FREE_DAILY_SECONDS', 300), 86_400)),
    familyClubDailySeconds: Math.max(0, Math.min(num(env, 'FAMILY_CLUB_DAILY_SECONDS', 1800), 86_400)),
    freeDailyTurns: Math.max(1, num(env, 'FREE_DAILY_TURNS', 60)),
    familyClubDailyTurns: Math.max(1, num(env, 'FAMILY_CLUB_DAILY_TURNS', 360)),
    turnCapSeconds: Math.max(1, num(env, 'TUTOR_TURN_CAP_SECONDS', 45)),
    sessionIdleSeconds: Math.max(10, num(env, 'SESSION_IDLE_SECONDS', 120)),
    realtimeGraceSeconds: Math.max(0, num(env, 'REALTIME_GRACE_SECONDS', 30)),
    retentionDays: Math.max(1, num(env, 'RETENTION_DAYS', 30)),
    monthlyBudgetUsd: positiveOr(num(env, 'MONTHLY_BUDGET_USD', DEFAULT_MONTHLY_BUDGET_USD), DEFAULT_MONTHLY_BUDGET_USD),
    maxBodyBytes: Math.max(1024, num(env, 'MAX_BODY_BYTES', 32 * 1024)),
    ipPerMinute: Math.max(1, num(env, 'RATE_LIMIT_IP_PER_MINUTE', 120)),
    sessionTurnsPerMinute: Math.max(1, num(env, 'RATE_LIMIT_SESSION_TURNS_PER_MINUTE', 30)),
    parentTokenTtlSeconds: Math.max(60, num(env, 'PARENT_TOKEN_TTL_SECONDS', 30 * 24 * 3600)),
    familyClubProductIds: (env.FAMILY_CLUB_PRODUCT_IDS || 'little_days.family_club.monthly,little_days.family_club.yearly').split(',').map((s) => s.trim()).filter(Boolean),
    priceHint: { currency: env.FAMILY_CLUB_PRICE_CURRENCY || 'THB', monthly: num(env, 'FAMILY_CLUB_PRICE_MONTHLY', 99), status: env.FAMILY_CLUB_PRICE_STATUS || 'proposed' },
    consentVersion: Math.max(1, Math.floor(num(env, 'CONSENT_VERSION', 1))),
    providerName,
    model: env.TUTOR_MODEL || 'gpt-4o-mini',
    standardPrimaryModel: env.STANDARD_PRIMARY_MODEL || '@cf/zai-org/glm-4.7-flash',
    standardFallbackModel: env.STANDARD_FALLBACK_MODEL || '@cf/google/gemma-4-26b-a4b-it',
    complexReasoningModel: env.COMPLEX_REASONING_MODEL || '@cf/openai/gpt-oss-120b',
    realtimeModel: env.REALTIME_MODEL || 'gpt-realtime-mini',
    realtimeVoice: env.REALTIME_VOICE || 'marin',
    realtimeTurnDetection: env.REALTIME_TURN_DETECTION === 'server_vad' ? 'server_vad' : 'semantic_vad',
    realtimeWsUrl: env.REALTIME_WS_URL || 'wss://api.openai.com/v1/realtime',
    providerTimeoutMs: Math.max(500, num(env, 'PROVIDER_TIMEOUT_MS', 6000)),
    hasOpenAiKey,
    standardProvider: env.STANDARD_PROVIDER === 'workers_ai' ? 'workers_ai' : env.STANDARD_PROVIDER === 'deepseek' ? 'deepseek' : env.STANDARD_PROVIDER === 'openai' ? 'openai' : 'mock',
    premiumLiveProvider: env.PREMIUM_LIVE_PROVIDER === 'gemini' ? 'gemini' : 'mock',
    providerBudgetCentsMonthly: Math.max(0, Math.floor(num(env, 'PROVIDER_BUDGET_CENTS_MONTHLY', 2500))),
    providerBudgetCentsDaily: Math.max(0, Math.floor(num(env, 'PROVIDER_BUDGET_CENTS_DAILY', 200))),
    planPolicies: planPolicies(env.PLAN_POLICY_JSON),
    storeProductMap: storeMap(env.STORE_PRODUCT_MAP_JSON),
  };
}

export function allowanceFor(config: Config, entitlement: Entitlement): { seconds: number; turns: number } {
  return entitlement === 'family_club'
    ? { seconds: config.familyClubDailySeconds, turns: config.familyClubDailyTurns }
    : { seconds: config.freeDailySeconds, turns: config.freeDailyTurns };
}
