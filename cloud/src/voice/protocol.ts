import type { VoiceClientEvent, VoiceServerEvent } from './types';

const CHILD_SAFE_ERROR = 'Let\'s keep learning another way.';

export function encodeEvent(event: VoiceClientEvent | VoiceServerEvent): string {
  return JSON.stringify(event);
}

export function parseClientEvent(raw: string): VoiceClientEvent | null {
  if (raw.length > 4096) return null;
  let value: unknown;
  try { value = JSON.parse(raw); } catch { return null; }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  if (typeof row.type !== 'string') return null;
  const short = (v: unknown, max = 128): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
  switch (row.type) {
    case 'session.start': return short(row.sessionId) && short(row.locale, 16) ? { type: row.type, sessionId: row.sessionId, locale: row.locale } : null;
    case 'audio.start': return short(row.turnId) && row.format === 'pcm16' && Number.isInteger(row.sampleRate) && Number(row.sampleRate) >= 8000 && Number(row.sampleRate) <= 48000 ? { type: row.type, turnId: row.turnId, format: 'pcm16', sampleRate: Number(row.sampleRate) } : null;
    case 'audio.end':
    case 'turn.interrupt':
    case 'turn.cancel': return short(row.turnId) ? { type: row.type, turnId: row.turnId } : null;
    case 'session.end': return short(row.sessionId) ? { type: row.type, sessionId: row.sessionId } : null;
    default: return null;
  }
}

export function safeVoiceError(code: string, retryable = false): VoiceServerEvent {
  return { type: 'error', code: normalizeReason(code), retryable, childMessage: CHILD_SAFE_ERROR };
}

function normalizeReason(value: string): Extract<VoiceServerEvent, { type: 'error' }>['code'] {
  const allowed = ['disabled', 'quota_exhausted', 'provider_unavailable', 'stt_failed', 'tts_failed', 'timeout', 'disconnected', 'invalid_event'] as const;
  return allowed.includes(value as typeof allowed[number]) ? value as typeof allowed[number] : 'provider_unavailable';
}
