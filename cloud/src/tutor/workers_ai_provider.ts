import type { ProviderTurnResult, TurnInput, TurnProvider, TurnUsage } from './provider_interface';

export interface WorkersAIBinding {
  run(model: string, input: Record<string, unknown>, options?: Record<string, unknown>): Promise<unknown>;
}

export interface AIMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';
  content: string;
}

export interface AITool {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface NormalizedToolCall {
  id?: string;
  name: string;
  arguments: Record<string, unknown>;
}

export interface WorkersAIUsage extends TurnUsage {
  totalTokens?: number;
}

export interface WorkersAIResult {
  text: string;
  parsed?: unknown;
  toolCalls: NormalizedToolCall[];
  usage: WorkersAIUsage;
  raw: unknown;
}

export type WorkersAIErrorCode = 'timeout' | 'rate_limited' | 'capacity' | 'invalid_response' | 'provider_error';

export class WorkersAIProviderError extends Error {
  constructor(
    public readonly code: WorkersAIErrorCode,
    message: string,
    public readonly retryable: boolean,
    public readonly status?: number,
  ) {
    super(message);
    this.name = 'WorkersAIProviderError';
  }
}

export interface WorkersAIProviderOptions {
  ai: WorkersAIBinding;
  model: string;
  timeoutMs?: number;
  gateway?: { id: string; skipCache?: boolean };
}

export class WorkersAIProvider {
  readonly name: string;
  private readonly timeoutMs: number;

  constructor(private readonly options: WorkersAIProviderOptions) {
    this.name = `workers-ai:${options.model}`;
    this.timeoutMs = options.timeoutMs ?? 8_000;
  }

  chat(input: { messages: AIMessage[]; maxTokens?: number; temperature?: number; signal?: AbortSignal }): Promise<WorkersAIResult> {
    return this.invoke({
      messages: input.messages,
      max_tokens: Math.max(input.maxTokens ?? 160, 1024),
      temperature: input.temperature ?? 0.2,
    }, input.signal);
  }

  structured(input: { messages: AIMessage[]; schema: Record<string, unknown>; maxTokens?: number; temperature?: number; signal?: AbortSignal }): Promise<WorkersAIResult> {
    const schemaBody = asRecord(input.schema.schema);
    return this.invoke({
      messages: input.messages,
      max_tokens: Math.max(input.maxTokens ?? 220, 1024),
      temperature: input.temperature ?? 0.2,
      response_format: { type: 'json_schema', json_schema: Object.keys(schemaBody).length ? schemaBody : input.schema },
    }, input.signal, true);
  }

  toolCall(input: { messages: AIMessage[]; tools: AITool[]; maxTokens?: number; temperature?: number; signal?: AbortSignal }): Promise<WorkersAIResult> {
    return this.invoke({
      messages: input.messages,
      tools: input.tools,
      max_tokens: Math.max(input.maxTokens ?? 160, 1024),
      temperature: input.temperature ?? 0.2,
    }, input.signal);
  }

  private async invoke(payload: Record<string, unknown>, signal?: AbortSignal, parseJson = false): Promise<WorkersAIResult> {
    if (signal?.aborted) throw new WorkersAIProviderError('timeout', 'Workers AI request was cancelled', true);
    const options: Record<string, unknown> = {};
    if (this.options.gateway) {
      options.gateway = {
        id: this.options.gateway.id,
        skipCache: this.options.gateway.skipCache ?? true,
      };
    }

    let timer: ReturnType<typeof setTimeout> | undefined;
    let abortListener: (() => void) | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new WorkersAIProviderError('timeout', 'Workers AI request timed out', true, 504)), this.timeoutMs);
      if (signal) {
        abortListener = () => reject(new WorkersAIProviderError('timeout', 'Workers AI request was cancelled', true));
        signal.addEventListener('abort', abortListener, { once: true });
      }
    });

    try {
      const raw = await Promise.race([this.options.ai.run(this.options.model, payload, options), timeout]);
      return normalizeResult(raw, parseJson);
    } catch (error) {
      if (error instanceof WorkersAIProviderError) throw error;
      throw classifyError(error);
    } finally {
      if (timer) clearTimeout(timer);
      if (signal && abortListener) signal.removeEventListener('abort', abortListener);
    }
  }
}

const TUTOR_SCHEMA: Record<string, unknown> = {
  name: 'tutor_turn',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['speech', 'subtitle', 'emotion', 'gesture', 'visual', 'lessonAction'],
    properties: {
      speech: { type: 'string', maxLength: 160 },
      subtitle: { type: 'string', maxLength: 160 },
      emotion: { enum: ['neutral', 'listening', 'thinking', 'happy', 'encouraging', 'smile'] },
      gesture: { enum: ['none', 'nod', 'tilt', 'point', 'clap', 'wave'] },
      visual: {
        type: 'object',
        additionalProperties: false,
        required: ['type'],
        properties: { type: { enum: ['none', 'flashcard', 'model'] }, assetId: { type: 'string' } },
      },
      lessonAction: { enum: ['next_question', 'retry', 'give_hint', 'complete', 'end_session', 'switch_lesson', 'jump_step'] },
      nextQuestion: { type: 'string', maxLength: 120 },
    },
  },
};

export function createWorkersAITurnProvider(options: WorkersAIProviderOptions): TurnProvider {
  const provider = new WorkersAIProvider(options);
  return {
    name: provider.name,
    async generateTurn(input: TurnInput): Promise<ProviderTurnResult> {
      const result = await provider.structured({
        signal: input.signal,
        messages: [
          {
            role: 'system',
            content: 'You are Aliz, a concise English learning companion for children. Use only the trusted lesson context. Never ask for personal data. Return the required JSON only.',
          },
          {
            role: 'user',
            content: JSON.stringify({ lessonId: input.lessonId, childResponse: input.transcript, lessonContext: input.lessonContext }),
          },
        ],
        schema: TUTOR_SCHEMA,
      });
      return { turn: result.parsed, usage: result.usage };
    },
  };
}

function normalizeResult(raw: unknown, parseJson: boolean): WorkersAIResult {
  const record = asRecord(raw);
  const nested = asRecord(record.result);
  const body = Object.keys(nested).length ? nested : record;
  const responseObject = asRecord(body.response);
  const firstChoice = Array.isArray(body.choices) ? asRecord(body.choices[0]) : {};
  const message = asRecord(firstChoice.message);
  const text = firstString(typeof raw === 'string' ? raw : undefined, body.response, body.text, body.content, message.content, record.response);
  const usage = normalizeUsage(asRecord(body.usage ?? record.usage));
  const toolCalls = normalizeToolCalls(body.tool_calls ?? body.toolCalls ?? responseObject.tool_calls ?? responseObject.toolCalls ?? message.tool_calls ?? record.tool_calls);
  let parsed: unknown;
  if (parseJson) {
    if (body.json !== undefined) parsed = body.json;
    else if (Object.keys(responseObject).length) parsed = responseObject;
    else if (text) {
      try { parsed = JSON.parse(stripJsonFence(text)); }
      catch { throw new WorkersAIProviderError('invalid_response', 'Workers AI returned malformed structured JSON', false); }
    } else if (Object.keys(body).length && !('usage' in body)) {
      parsed = body;
    } else {
      throw new WorkersAIProviderError('invalid_response', 'Workers AI returned no structured response', false);
    }
  }
  if (!parseJson && !text && toolCalls.length === 0) {
    throw new WorkersAIProviderError('invalid_response', 'Workers AI returned no text or tool call', false);
  }
  return { text, parsed, toolCalls, usage, raw };
}

function normalizeUsage(value: Record<string, unknown>): WorkersAIUsage {
  const input = numberValue(value.prompt_tokens, value.input_tokens, value.promptTokens, value.inputTokens);
  const output = numberValue(value.completion_tokens, value.output_tokens, value.completionTokens, value.outputTokens);
  const cached = numberValue(value.cached_tokens, value.cached_input_tokens, value.cachedInputTokens);
  const total = numberValue(value.total_tokens, value.totalTokens) || input + output;
  return {
    llmInputTokens: input,
    llmOutputTokens: output,
    ...(cached ? { cachedInputTokens: cached } : {}),
    ...(total ? { totalTokens: total } : {}),
  };
}

function normalizeToolCalls(value: unknown): NormalizedToolCall[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((candidate) => {
    const call = asRecord(candidate);
    const fn = asRecord(call.function);
    const name = firstString(fn.name, call.name);
    if (!name) return [];
    const rawArgs = fn.arguments ?? call.arguments ?? {};
    let args: Record<string, unknown>;
    if (typeof rawArgs === 'string') {
      try { args = asRecord(JSON.parse(rawArgs)); } catch { return []; }
    } else args = asRecord(rawArgs);
    return [{ ...(typeof call.id === 'string' ? { id: call.id } : {}), name, arguments: args }];
  });
}

function classifyError(error: unknown): WorkersAIProviderError {
  const r = asRecord(error);
  const status = numberValue(r.status, r.statusCode) || undefined;
  const message = error instanceof Error ? error.message : firstString(r.message) || 'Workers AI request failed';
  const lower = message.toLowerCase();
  if (status === 429 || lower.includes('rate limit') || lower.includes('too many requests')) {
    return new WorkersAIProviderError('rate_limited', message, true, status ?? 429);
  }
  if (status === 503 || status === 529 || lower.includes('capacity') || lower.includes('overloaded')) {
    return new WorkersAIProviderError('capacity', message, true, status ?? 503);
  }
  return new WorkersAIProviderError('provider_error', message, Boolean(status && status >= 500), status);
}

function stripJsonFence(value: string): string {
  return value.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function firstString(...values: unknown[]): string {
  return values.find((v) => typeof v === 'string') as string ?? '';
}

function numberValue(...values: unknown[]): number {
  const value = values.find((v) => typeof v === 'number' && Number.isFinite(v));
  return typeof value === 'number' ? Math.max(0, Math.trunc(value)) : 0;
}
