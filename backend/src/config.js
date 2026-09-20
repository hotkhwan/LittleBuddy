// Configuration from process.env with safe defaults. No secrets are defaulted.
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const BACKEND_ROOT = path.resolve(HERE, '..');
export const REPO_ROOT = path.resolve(BACKEND_ROOT, '..');

/**
 * @param {Record<string, string | undefined>} env
 * @param {(key: string, fallback: number) => number} num
 */
function makeNum(env) {
  return (key, fallback) => {
    const raw = env[key];
    if (raw === undefined || raw === '') return fallback;
    const n = Number(raw);
    return Number.isFinite(n) ? n : fallback;
  };
}

/**
 * @typedef {ReturnType<typeof loadConfig>} Config
 */

/**
 * Build the runtime config. Pure: no I/O.
 * @param {Record<string, string | undefined>} [env]
 */
export function loadConfig(env = process.env) {
  const num = makeNum(env);
  const devMode = env.DEV_MODE === '1' || env.DEV_MODE === 'true';
  const provider = (env.TUTOR_PROVIDER || (env.OPENAI_API_KEY ? 'openai' : 'mock')).toLowerCase();
  return {
    devMode,
    host: env.HOST || '127.0.0.1',
    port: num('PORT', 8787),
    corsOrigin: env.CORS_ORIGIN || '*',
    dataDir: env.DATA_DIR || path.join(BACKEND_ROOT, 'data'),
    maxBodyBytes: num('MAX_BODY_BYTES', 32 * 1024),
    handlerTimeoutMs: num('HANDLER_TIMEOUT_MS', 10_000),
    providerTimeoutMs: num('PROVIDER_TIMEOUT_MS', 6_000),
    // quota
    freeDailySeconds: num('FREE_DAILY_SECONDS', 300),
    familyClubDailySeconds: num('FAMILY_CLUB_DAILY_SECONDS', 1800),
    turnCapSeconds: num('TUTOR_TURN_CAP_SECONDS', 45),
    // parental approval
    parentApprovalSecret: env.PARENT_APPROVAL_SECRET || '',
    devParentApprovalToken: env.DEV_PARENT_APPROVAL_TOKEN || 'dev-parent-approval',
    parentApprovalTtlSeconds: num('PARENT_APPROVAL_TTL_SECONDS', 30 * 24 * 3600),
    // provider
    provider,
    openaiApiKey: env.OPENAI_API_KEY || '',
    openaiBaseUrl: env.OPENAI_BASE_URL || 'https://api.openai.com/v1',
    openaiExtraHeaders: parseJsonObject(env.OPENAI_EXTRA_HEADERS),
    model: env.TUTOR_MODEL || 'gpt-4o-mini',
    // cost model
    monthlyBudgetUsd: env.MONTHLY_BUDGET_USD ? num('MONTHLY_BUDGET_USD', 0) : null,
    sttMode: env.STT_MODE === 'cloud' ? 'cloud' : 'device',
    sttModel: env.STT_MODEL || 'gpt-4o-mini-transcribe',
    ttsMode: env.TTS_MODE === 'cloud' ? 'cloud' : 'device',
    ttsModel: env.TTS_MODEL || 'tts-1',
    turnCacheTtlSeconds: num('TURN_CACHE_TTL_SECONDS', 86_400),
    turnCacheMaxEntries: num('TURN_CACHE_MAX_ENTRIES', 5000),
    // rate limits
    ipPerMinute: num('RATE_LIMIT_IP_PER_MINUTE', 120),
    sessionTurnsPerMinute: num('RATE_LIMIT_SESSION_TURNS_PER_MINUTE', 30),
    // content paths (shared with the game; read-only for the backend)
    allowlistPath: env.TUTOR_ALLOWLIST_PATH || path.join(REPO_ROOT, 'game', 'content', 'tutor', 'assets_allowlist.json'),
    pricesPath: env.TUTOR_PRICES_PATH || path.join(BACKEND_ROOT, 'config', 'prices.json'),
  };
}

/** @param {string | undefined} raw */
function parseJsonObject(raw) {
  if (!raw) return {};
  try {
    const v = JSON.parse(raw);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
  } catch {
    return {};
  }
}
