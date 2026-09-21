// Free-chat configuration and the gate that decides whether a session may be
// opened in `mode: "chat"`. Read from env, every number bounded, and OFF by
// default: `FREE_CHAT_ENABLED` is "false" in code, and even when it is set the
// mode is honoured in DEV_MODE only until the privacy gates
// (docs/ALIZ_TUTOR_PRIVACY_REVIEW.md) pass. Production-shaped env (DEV_MODE=0)
// therefore always answers 403 feature_disabled, whatever the flag says.
import type { Config, Env } from '../env';
import { ApiError } from '../errors';

/** Env names read here (names only in .dev.vars.example; plain vars, never secrets). */
export interface ChatEnvVars {
  FREE_CHAT_ENABLED?: string;
  CHAT_CONTEXT_TURNS?: string;
  CHAT_RESPONSE_MAX_WORDS?: string;
  CHAT_MAX_OUTPUT_TOKENS?: string;
}

export interface ChatConfig {
  enabled: boolean;
  /** Rolling window: how many child/tutor EXCHANGES the model sees (K). */
  contextTurns: number;
  /** Default spoken-word cap for a chat reply; a turn may ask for another value within the bounds. */
  responseMaxWords: number;
  /** Provider max output tokens for one chat reply. */
  maxOutputTokens: number;
}

export const CHAT_MIN_WORDS = 8;
export const CHAT_MAX_WORDS = 40;
export const CHAT_DEFAULT_WORDS = 25;
export const CHAT_MIN_CONTEXT_TURNS = 0;
export const CHAT_MAX_CONTEXT_TURNS = 12;
export const CHAT_DEFAULT_CONTEXT_TURNS = 6;
export const CHAT_MIN_OUTPUT_TOKENS = 40;
export const CHAT_MAX_OUTPUT_TOKENS = 400;
export const CHAT_DEFAULT_OUTPUT_TOKENS = 160;
/** The lessonId a chat session is recorded under (numbers/ids in D1 only). */
export const CHAT_LESSON_ID = 'free_chat';

export type SessionMode = 'lesson' | 'chat';
export const SESSION_MODES: readonly SessionMode[] = ['lesson', 'chat'];

function bounded(raw: string | undefined, fallback: number, min: number, max: number): number {
  if (raw === undefined || raw === null || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(n)));
}

/** Pure: no I/O. */
export function loadChatConfig(env: Env & ChatEnvVars): ChatConfig {
  const flag = (env.FREE_CHAT_ENABLED || '').trim().toLowerCase();
  return {
    enabled: flag === '1' || flag === 'true',
    contextTurns: bounded(env.CHAT_CONTEXT_TURNS, CHAT_DEFAULT_CONTEXT_TURNS, CHAT_MIN_CONTEXT_TURNS, CHAT_MAX_CONTEXT_TURNS),
    responseMaxWords: bounded(env.CHAT_RESPONSE_MAX_WORDS, CHAT_DEFAULT_WORDS, CHAT_MIN_WORDS, CHAT_MAX_WORDS),
    maxOutputTokens: bounded(env.CHAT_MAX_OUTPUT_TOKENS, CHAT_DEFAULT_OUTPUT_TOKENS, CHAT_MIN_OUTPUT_TOKENS, CHAT_MAX_OUTPUT_TOKENS),
  };
}

/** Chat is reachable only when the flag is on AND the Worker runs in DEV_MODE. */
export function chatAllowed(config: Config, chat: ChatConfig): boolean {
  return Boolean(config.devMode) && chat.enabled;
}

export function featureDisabled(feature = 'free_chat'): ApiError {
  return new ApiError(403, 'feature_disabled', 'That feature is not available on this server.', { feature });
}

/** Clamp a requested per-turn word cap into the allowed band (anything odd -> the default). */
export function clampResponseWords(requested: unknown, fallback: number): number {
  if (requested === undefined || requested === null || requested === '') return fallback;
  const n = typeof requested === 'number' ? requested : Number(requested);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(CHAT_MIN_WORDS, Math.min(CHAT_MAX_WORDS, Math.floor(n)));
}
