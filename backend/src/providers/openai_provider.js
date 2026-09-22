// OpenAI adapter, enabled only when OPENAI_API_KEY is set on the SERVER.
// The game never sees the key. Uses Chat Completions with a strict JSON
// schema mirroring TutorTurn, a short system prompt tuned for ages 3-6, and
// a fetch injected for tests (never called for real in this repo's tests).
//
// Privacy / data retention:
// - The request carries only: the lesson context (step, expected answers,
//   hint, next question, asset id) and the child's transcript for this turn.
//   No name, age, device id, clientId, session id or location is ever sent.
// - `store: false` asks OpenAI not to retain the completion in dashboard logs.
// - Zero Data Retention (ZDR) is an org-level arrangement with OpenAI; once
//   granted, no header is needed, but this adapter exposes `extraHeaders`
//   (env OPENAI_EXTRA_HEADERS as JSON) as the hook for any per-request
//   header a data-processing agreement requires (e.g. project scoping).
import { EMOTIONS, GESTURES, LESSON_ACTIONS, MAX_NEXT_QUESTION, MAX_SPEECH, MAX_SUBTITLE, VISUAL_TYPES } from '../turn_validator.js';

export const SYSTEM_PROMPT = [
  'You are Aliz, a warm, patient English tutor for children aged 3 to 6 who are learning English as a second language.',
  `Reply with ONE short spoken line (max ${MAX_SPEECH} characters), simple words, present tense, plain ASCII letters and punctuation only (no emoji, no curly quotes).`,
  'Always be kind: praise real effort, never say wrong, no, bad, or scores. Use Great!, Nice!, or Let\'s try together!',
  'Follow the lesson context exactly: if outcome is correct, celebrate briefly and ask the next question given; if incorrect, give the provided hint; if unclear, gently ask again.',
  'Never ask the child personal questions (name, age, home, school, family, location). Never mention the internet, links, prices, or other apps.',
  'Only use the visual asset id given in the context, or none.',
].join(' ');

/** Strict JSON schema mirroring TutorTurn (all fields required; nullable optionals). */
export const TUTOR_TURN_SCHEMA = Object.freeze({
  name: 'tutor_turn',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['speech', 'subtitle', 'emotion', 'gesture', 'visual', 'lessonAction', 'nextQuestion'],
    properties: {
      speech: { type: 'string', description: `Spoken line, <= ${MAX_SPEECH} chars, ASCII only.` },
      subtitle: { type: ['string', 'null'], description: `Caption, <= ${MAX_SUBTITLE} chars, usually equal to speech.` },
      emotion: { type: 'string', enum: [...EMOTIONS] },
      gesture: { type: 'string', enum: [...GESTURES] },
      visual: {
        type: 'object',
        additionalProperties: false,
        required: ['type', 'assetId'],
        properties: {
          type: { type: 'string', enum: [...VISUAL_TYPES] },
          assetId: { type: ['string', 'null'] },
        },
      },
      lessonAction: { type: 'string', enum: [...LESSON_ACTIONS] },
      nextQuestion: { type: ['string', 'null'], description: `<= ${MAX_NEXT_QUESTION} chars.` },
    },
  },
});

/**
 * Build the user message: lesson context + transcript only. Nothing else.
 * @param {{transcript: string, lessonId: string, lessonContext: import('../types.js').LessonContext}} input
 */
export function buildUserMessage({ transcript, lessonId, lessonContext }) {
  const ctx = lessonContext ?? {};
  const lines = [
    `lessonId: ${lessonId}`,
    `stepId: ${ctx.stepId ?? ''}`,
    `outcome: ${ctx.outcome ?? 'unclear'}`,
    `expectedAnswers: ${(ctx.expectedAnswers ?? []).join(', ')}`,
    `hint: ${ctx.hint ?? ''}`,
    `nextQuestionText: ${ctx.nextQuestionText ?? ''}`,
    `visualAssetId: ${ctx.visualAssetId ?? ''}`,
    `childSaid: ${String(transcript ?? '').slice(0, 200)}`,
  ];
  return lines.join('\n');
}

/**
 * Normalise common non-ASCII output so it passes the strict validator.
 * @param {unknown} s
 */
export function asciiNormalize(s) {
  if (typeof s !== 'string') return s;
  return s
    .replace(/[‘’‚′]/g, "'")
    .replace(/[“”„″]/g, '"')
    .replace(/[–—―]/g, '-')
    .replace(/…/g, '...')
    .replace(/ /g, ' ')
    .replace(/[^\x20-\x7E]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * @param {{apiKey: string, model?: string, baseUrl?: string, fetchImpl?: typeof fetch, extraHeaders?: Record<string, string>, maxOutputTokens?: number}} opts
 * @returns {import('../types.js').ConversationProvider}
 */
export function createOpenAIProvider(opts) {
  if (!opts.apiKey) throw new Error('OPENAI_API_KEY is required for the openai provider');
  const model = opts.model || 'gpt-5.6-luna';
  const baseUrl = (opts.baseUrl || 'https://api.openai.com/v1').replace(/\/+$/, '');
  const fetchImpl = opts.fetchImpl || globalThis.fetch;
  const extraHeaders = opts.extraHeaders || {};
  const maxOutputTokens = opts.maxOutputTokens || 160;

  return {
    name: `openai:${model}`,
    async generateTurn({ transcript, lessonId, lessonContext, signal }) {
      const body = {
        model,
        store: false,
        temperature: 0.4,
        max_tokens: maxOutputTokens,
        response_format: { type: 'json_schema', json_schema: TUTOR_TURN_SCHEMA },
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: buildUserMessage({ transcript, lessonId, lessonContext }) },
        ],
      };
      const res = await fetchImpl(`${baseUrl}/chat/completions`, {
        method: 'POST',
        // Extra headers first so they can never override the credentials or content type (finding L6).
        headers: { ...extraHeaders, 'content-type': 'application/json', authorization: `Bearer ${opts.apiKey}` },
        body: JSON.stringify(body),
        signal,
      });
      if (!res.ok) {
        const err = new Error(`openai http ${res.status}`);
        err.status = res.status;
        throw err;
      }
      const json = await res.json();
      const choice = json?.choices?.[0];
      if (!choice || choice.finish_reason === 'content_filter' || choice.message?.refusal) {
        throw new Error('openai returned no usable completion');
      }
      let parsed;
      try {
        parsed = JSON.parse(choice.message?.content ?? '');
      } catch {
        throw new Error('openai returned non-JSON content');
      }
      const turn = {
        ...parsed,
        speech: asciiNormalize(parsed.speech),
        subtitle: parsed.subtitle == null ? undefined : asciiNormalize(parsed.subtitle),
        nextQuestion: parsed.nextQuestion == null ? undefined : asciiNormalize(parsed.nextQuestion),
        visual: parsed.visual && { type: parsed.visual.type, assetId: parsed.visual.assetId == null ? undefined : parsed.visual.assetId },
      };
      const usage = json.usage ?? {};
      return {
        turn,
        usage: {
          llmInputTokens: usage.prompt_tokens ?? 0,
          llmOutputTokens: usage.completion_tokens ?? 0,
          cachedInputTokens: usage.prompt_tokens_details?.cached_tokens ?? 0,
        },
      };
    },
  };
}
