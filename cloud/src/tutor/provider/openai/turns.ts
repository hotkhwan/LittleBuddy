// The OpenAI turn provider: lesson turns (TurnProvider) and free-chat turns
// (ChatTurnProvider) over Chat Completions with structured output. Returns
// the RAW parsed object; the Worker validates it (validateTurn / gateChatTurn)
// and falls back to the mock when it is invalid, so nothing here is trusted.
// Invalid JSON or a refusal is returned as `turn: null` (-> validator says
// turn:not_object -> mock fallback) rather than thrown, so one bad reply is
// a fallback and not an error path.
import type { ProviderTurnResult, TurnInput, TurnProvider, TurnUsage } from '../../provider_interface';
import type { ChatTurnInput, ChatTurnProvider } from '../../chat_provider';
import { chatCompletions, type ChatCompletionUsage, type ClientOptions } from './client';
import { buildChatSystemPrompt, buildLessonSystemPrompt, chatMessages, lessonUserMessage } from './prompts';
import { CHAT_TURN_ACTIONS, LESSON_TURN_ACTIONS, responseFormat, tutorTurnJsonSchema } from './schema';

export interface OpenAITurnOptions {
  model: string;
  client: ClientOptions;
  assetIds: readonly string[];
  temperature: number;
  maxOutputTokens: number;
}

export const DEFAULT_TEMPERATURE = 0.3;
export const DEFAULT_MAX_OUTPUT_TOKENS = 160;

export function createOpenAITurnProvider(o: OpenAITurnOptions): TurnProvider & ChatTurnProvider {
  const name = `openai:${o.model}`;
  const lessonFormat = responseFormat('tutor_turn', tutorTurnJsonSchema({ lessonActions: LESSON_TURN_ACTIONS, assetIds: o.assetIds }));
  const chatFormat = responseFormat('tutor_chat_turn', tutorTurnJsonSchema({ lessonActions: CHAT_TURN_ACTIONS, assetIds: o.assetIds }));

  async function complete(messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }>, format: Record<string, unknown>, signal: AbortSignal): Promise<ProviderTurnResult> {
    const r = await chatCompletions(o.client, { model: o.model, messages, temperature: o.temperature, max_tokens: o.maxOutputTokens, response_format: format }, signal);
    return { turn: parseTurn(r.content), usage: usageOf(r.usage) };
  }

  return {
    name,
    async generateTurn(input: TurnInput): Promise<ProviderTurnResult> {
      const messages = [
        { role: 'system' as const, content: buildLessonSystemPrompt(input.lessonId, input.lessonContext) },
        { role: 'user' as const, content: lessonUserMessage(input.transcript ?? '') },
      ];
      return complete(messages, lessonFormat, input.signal);
    },
    async generateChatTurn(input: ChatTurnInput): Promise<ProviderTurnResult> {
      const messages = [
        { role: 'system' as const, content: buildChatSystemPrompt(input.responseMaxWords, o.assetIds) },
        ...chatMessages(input.history, input.transcript ?? ''),
      ];
      return complete(messages, chatFormat, input.signal);
    },
  };
}

/** Parses the structured-output content; anything but a JSON object becomes null. */
export function parseTurn(content: string | null): unknown {
  if (!content) return null;
  try {
    const parsed: unknown = JSON.parse(content);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    const t = { ...(parsed as Record<string, unknown>) };
    // Structured output cannot express "optional": empty strings mean absent.
    if (t.nextQuestion === '') delete t.nextQuestion;
    const visual = t.visual as Record<string, unknown> | undefined;
    if (visual && typeof visual === 'object' && !Array.isArray(visual)) {
      const v = { ...visual };
      if (v.assetId === '') delete v.assetId;
      t.visual = v;
    }
    if (typeof t.speech === 'string' && (t.subtitle === undefined || t.subtitle === '')) t.subtitle = t.speech;
    return t;
  } catch {
    return null;
  }
}

function usageOf(u: ChatCompletionUsage): TurnUsage {
  const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.round(v) : 0);
  const out: TurnUsage = { llmInputTokens: n(u.prompt_tokens), llmOutputTokens: n(u.completion_tokens) };
  const cached = n(u.prompt_tokens_details?.cached_tokens);
  if (cached) out.cachedInputTokens = cached;
  return out;
}
