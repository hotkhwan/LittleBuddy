import { TUTOR_TURN_SCHEMA, SYSTEM_PROMPT, asciiNormalize, buildUserMessage } from './openai_provider.js';

/** DeepSeek's OpenAI-compatible adapter. It is opt-in and never selected by default. */
export function createDeepSeekProvider(opts = {}) {
  if (!opts.apiKey) throw new Error('DEEPSEEK_API_KEY is required for the deepseek provider');
  const model = opts.model || 'deepseek-flash';
  const baseUrl = (opts.baseUrl || 'https://api.deepseek.com').replace(/\/+$/, '');
  const fetchImpl = opts.fetchImpl || globalThis.fetch;
  return {
    name: `deepseek:${model}`,
    model,
    async generateTurn({ transcript, lessonId, lessonContext, signal }) {
      const res = await fetchImpl(`${baseUrl}/chat/completions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${opts.apiKey}` },
        body: JSON.stringify({
          model,
          temperature: 0.4,
          max_tokens: opts.maxOutputTokens || 160,
          response_format: { type: 'json_object' },
          messages: [
            { role: 'system', content: `${SYSTEM_PROMPT} Return JSON matching this schema: ${JSON.stringify(TUTOR_TURN_SCHEMA.schema)}` },
            { role: 'user', content: buildUserMessage({ transcript, lessonId, lessonContext }) },
          ],
        }),
        signal,
      });
      if (!res.ok) {
        const error = new Error(`deepseek http ${res.status}`);
        error.status = res.status;
        throw error;
      }
      const json = await res.json();
      let parsed;
      try { parsed = JSON.parse(json?.choices?.[0]?.message?.content ?? ''); } catch { throw new Error('deepseek returned non-JSON content'); }
      return {
        turn: {
          ...parsed,
          speech: asciiNormalize(parsed.speech),
          subtitle: parsed.subtitle == null ? undefined : asciiNormalize(parsed.subtitle),
          nextQuestion: parsed.nextQuestion == null ? undefined : asciiNormalize(parsed.nextQuestion),
          visual: parsed.visual && { type: parsed.visual.type, assetId: parsed.visual.assetId == null ? undefined : parsed.visual.assetId },
        },
        usage: {
          llmInputTokens: json.usage?.prompt_tokens ?? 0,
          llmOutputTokens: json.usage?.completion_tokens ?? 0,
          cachedInputTokens: json.usage?.prompt_cache_hit_tokens ?? 0,
        },
      };
    },
  };
}
