// OpenAI Realtime API: ephemeral client-secret minting (server side only).
//
// Source (fetched 2026-09-20):
//   https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create
//     POST /v1/realtime/client_secrets
//     body.expires_after { anchor: "created_at" (only value, default), seconds: 10..7200 (default 600) }
//     body.session { type: "realtime" | "transcription", model, instructions, output_modalities,
//                    audio.input.{format, noise_reduction{type: near_field|far_field},
//                                 transcription{model, language, prompt},
//                                 turn_detection{type: server_vad{threshold=0.5, prefix_padding_ms=300,
//                                                silence_duration_ms=500, idle_timeout_ms, create_response,
//                                                interrupt_response} | semantic_vad{eagerness: low|medium|high|auto,
//                                                create_response, interrupt_response}}},
//                    audio.output.{voice: alloy|ash|ballad|coral|echo|sage|shimmer|verse|marin|cedar, speed 0.25..1.5},
//                    tools, tool_choice: none|auto|required, max_output_tokens: 1..4096|"inf", truncation }
//     response { value: "ek_...", expires_at: <unix seconds>, session: {...} }
//   https://developers.openai.com/api/docs/guides/realtime-vad  (server_vad vs semantic_vad wording)
//   https://developers.openai.com/api/docs/guides/realtime       (client_secrets for browser/mobile; no OpenAI-Beta header on GA)
//
// The game receives only the ephemeral `value` (ek_...), never OPENAI_API_KEY.
// The expiry is chosen by the caller (app.js) as min(remaining quota + 30 s, 7200)
// so the token itself bounds the session even if the client never reports.
import { MAX_SPEECH } from '../turn_validator.js';

export const REALTIME_CLIENT_SECRETS_PATH = '/realtime/client_secrets';
export const REALTIME_MIN_EXPIRY_SECONDS = 10;
export const REALTIME_MAX_EXPIRY_SECONDS = 7200;
export const REALTIME_VOICES = Object.freeze(['alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse', 'marin', 'cedar']);

/**
 * Instructions for a realtime lesson session. Built from the SERVER's lesson
 * file (never from client text) and the same child-safety rules as the
 * turn-based system prompt. No PII: no name, age, clientId, session id.
 * @param {import('../lessons.js').Lesson} lesson
 */
export function buildRealtimeInstructions(lesson) {
  const steps = lesson.steps
    .map((s, i) => {
      if (s.kind === 'ask') return `${i + 1}. ASK: "${s.questionText}" (accept: ${(s.expectedAnswers ?? []).join(' / ')}; hint: "${s.hint}"; when right say: "${s.successLine}")`;
      return `${i + 1}. ${s.kind.toUpperCase()}: "${s.teachText}"`;
    })
    .join('\n');
  return [
    'You are Aliz, a warm, patient English tutor for children aged 3 to 6 who are learning English as a second language.',
    `Speak in very short sentences (each reply under ${MAX_SPEECH} characters), slowly and clearly, simple words, present tense.`,
    "Always be kind: praise real effort, never say wrong, no, bad, or give scores. Use Great!, Nice!, or Let's try together!",
    'Never ask the child personal questions (name, age, home, school, family, location). Never mention the internet, links, prices, or other apps. Stay on the lesson.',
    'If you cannot understand the child, gently ask again once, then give the hint, then move on. Never make the child feel they failed.',
    `Lesson "${lesson.title || lesson.lessonId}". Follow these steps in order and stop after the last one:`,
    steps,
  ].join('\n');
}

/**
 * @param {{apiKey: string, model?: string, baseUrl?: string, fetchImpl?: typeof fetch, voice?: string, transcriptionModel?: string, extraHeaders?: Record<string, string>}} opts
 */
export function createRealtimeTokenMinter(opts) {
  if (!opts.apiKey) throw new Error('OPENAI_API_KEY is required to mint realtime client secrets');
  const model = opts.model || 'gpt-realtime-mini';
  const baseUrl = (opts.baseUrl || 'https://api.openai.com/v1').replace(/\/+$/, '');
  const fetchImpl = opts.fetchImpl || globalThis.fetch;
  const voice = REALTIME_VOICES.includes(opts.voice ?? '') ? opts.voice : 'marin';
  const transcriptionModel = opts.transcriptionModel || 'gpt-4o-mini-transcribe';
  const extraHeaders = opts.extraHeaders || {};

  /**
   * Build the exact request body sent to OpenAI (exported for tests/docs).
   * @param {{instructions: string, expiresSeconds: number, turnDetection?: 'server_vad'|'semantic_vad', eagerness?: 'low'|'medium'|'high'|'auto', transcription?: boolean}} p
   */
  function buildRequest(p) {
    const seconds = Math.max(REALTIME_MIN_EXPIRY_SECONDS, Math.min(REALTIME_MAX_EXPIRY_SECONDS, Math.round(p.expiresSeconds)));
    const turnDetection = p.turnDetection === 'server_vad'
      ? { type: 'server_vad', threshold: 0.6, prefix_padding_ms: 300, silence_duration_ms: 700, create_response: true, interrupt_response: true }
      : { type: 'semantic_vad', eagerness: p.eagerness ?? 'low', create_response: true, interrupt_response: true };
    return {
      expires_after: { anchor: 'created_at', seconds },
      session: {
        type: 'realtime',
        model,
        instructions: p.instructions,
        output_modalities: ['audio'],
        max_output_tokens: 400,
        tool_choice: 'none',
        tools: [],
        audio: {
          input: {
            noise_reduction: { type: 'near_field' },
            transcription: p.transcription === false ? undefined : { model: transcriptionModel, language: 'en' },
            turn_detection: turnDetection,
          },
          output: { voice, speed: 0.9 },
        },
      },
    };
  }

  /**
   * @param {{instructions: string, expiresSeconds: number, turnDetection?: 'server_vad'|'semantic_vad', eagerness?: 'low'|'medium'|'high'|'auto', transcription?: boolean, signal?: AbortSignal}} p
   * @returns {Promise<{value: string, expiresAt: string, model: string, turnDetection: string}>}
   */
  async function mint(p) {
    const body = buildRequest(p);
    const res = await fetchImpl(`${baseUrl}${REALTIME_CLIENT_SECRETS_PATH}`, {
      method: 'POST',
      headers: { ...extraHeaders, 'content-type': 'application/json', authorization: `Bearer ${opts.apiKey}` },
      body: JSON.stringify(body),
      signal: p.signal,
    });
    if (!res.ok) {
      const err = new Error(`openai realtime client_secrets http ${res.status}`);
      err.status = res.status;
      throw err;
    }
    const json = await res.json();
    if (typeof json?.value !== 'string' || !json.value) throw new Error('openai realtime client_secrets returned no value');
    const expiresAt = typeof json.expires_at === 'number' ? new Date(json.expires_at * 1000).toISOString() : new Date(Date.now() + body.expires_after.seconds * 1000).toISOString();
    return { value: json.value, expiresAt, model, turnDetection: body.session.audio.input.turn_detection.type };
  }

  return { name: `openai-realtime:${model}`, model, mint, buildRequest };
}
