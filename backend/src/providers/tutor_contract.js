export const TUTOR_MODES = Object.freeze(['lesson_local', 'standard_chat', 'premium_live']);
export const TUTOR_TIERS = Object.freeze(['standard', 'premium']);
export const AUDIO_MODES = Object.freeze(['device', 'streaming']);

const MODE_CAPABILITIES = Object.freeze({
  lesson_local: Object.freeze(['lessons', 'touch', 'device_speech']),
  standard_chat: Object.freeze(['text_chat', 'device_speech']),
  premium_live: Object.freeze(['live_audio', 'barge_in', 'interruption', 'output_transcription']),
});

/** Provider-neutral metadata safe to return to a client. */
export function sessionMetadata({ tier = 'standard', mode = 'lesson_local', quotaRemaining = 0, capabilities } = {}) {
  if (!TUTOR_TIERS.includes(tier)) throw new TypeError('invalid tutor tier');
  if (!TUTOR_MODES.includes(mode)) throw new TypeError('invalid tutor mode');
  return Object.freeze({
    tier,
    mode,
    capabilities: Object.freeze([...(capabilities ?? MODE_CAPABILITIES[mode])]),
    quota_remaining: Math.max(0, Number(quotaRemaining) || 0),
    audio_mode: mode === 'premium_live' ? 'streaming' : 'device',
  });
}

export function usageRecord(input = {}) {
  return {
    text_input_tokens: nonNegative(input.text_input_tokens),
    text_output_tokens: nonNegative(input.text_output_tokens),
    audio_input_seconds: nonNegative(input.audio_input_seconds),
    audio_output_seconds: nonNegative(input.audio_output_seconds),
    session_seconds: nonNegative(input.session_seconds),
    provider: String(input.provider || 'mock'),
    model: String(input.model || 'mock'),
    tier: TUTOR_TIERS.includes(input.tier) ? input.tier : 'standard',
  };
}

function nonNegative(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}
