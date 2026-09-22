import { usageRecord } from './tutor_contract.js';

export const GEMINI_LIVE_EVENTS = Object.freeze(['open', 'audio', 'transcript', 'interrupted', 'reconnecting', 'close', 'error']);

/**
 * Backend-owned Gemini Live session. transportFactory is injected so tests and
 * production Worker transports share lifecycle semantics without exposing a key.
 */
export function createGeminiLiveProvider(opts = {}) {
  if (!opts.apiKey) throw new Error('GEMINI_API_KEY is required for the gemini live provider');
  if (typeof opts.transportFactory !== 'function') throw new TypeError('transportFactory is required');
  const model = opts.model || 'gemini-3.8-live';
  const maxReconnects = Math.max(0, opts.maxReconnects ?? 1);

  function createSession({ onEvent = () => {}, quotaRemainingSeconds = 0, signal } = {}) {
    let transport;
    let state = 'idle';
    let reconnects = 0;
    const startedAt = Date.now();
    let audioInputSeconds = 0;
    let audioOutputSeconds = 0;

    const emit = (type, data = {}) => { if (GEMINI_LIVE_EVENTS.includes(type)) onEvent({ type, ...data }); };
    const bind = (next) => {
      next.onmessage = (event) => {
        const message = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
        if (message.type === 'audio') audioOutputSeconds += Number(message.durationSeconds) || 0;
        emit(message.type, message);
      };
      next.onclose = async () => {
        if (state === 'closing' || state === 'closed') return;
        if (reconnects >= maxReconnects) { state = 'closed'; emit('close', { fallbackMode: 'standard_chat' }); return; }
        reconnects += 1;
        state = 'reconnecting'; emit('reconnecting', { attempt: reconnects });
        await connect();
      };
      next.onerror = (error) => emit('error', { message: String(error?.message || 'live transport error') });
    };
    async function connect() {
      if (signal?.aborted) throw signal.reason;
      transport = await opts.transportFactory({ apiKey: opts.apiKey, model, signal });
      bind(transport);
      state = 'open'; emit('open', { reconnected: reconnects > 0 });
    }
    return {
      get state() { return state; },
      get model() { return model; },
      async connect() { if (state !== 'idle' && state !== 'reconnecting') return; await connect(); },
      sendAudio(audio, durationSeconds = 0) {
        if (state !== 'open') throw new Error('live session is not open');
        const duration = Math.max(0, Number(durationSeconds) || 0);
        if (audioInputSeconds + duration > quotaRemainingSeconds) throw new Error('premium live quota exhausted');
        audioInputSeconds += duration;
        transport.send({ type: 'audio', audio });
      },
      interrupt() {
        if (state !== 'open') return false;
        transport.send({ type: 'interrupt' });
        emit('interrupted');
        return true;
      },
      close() {
        if (state === 'closed') return;
        state = 'closing'; transport?.close(); state = 'closed'; emit('close', { fallbackMode: null });
      },
      usage() {
        return usageRecord({ audio_input_seconds: audioInputSeconds, audio_output_seconds: audioOutputSeconds, session_seconds: (Date.now() - startedAt) / 1000, provider: 'gemini', model, tier: 'premium' });
      },
    };
  }
  return { name: `gemini-live:${model}`, model, createSession };
}
