// The ONE place the Worker talks to the vendor: Chat Completions over an
// injectable fetch. Timeout per attempt, one retry on a transient failure,
// honours the caller's abort signal, and NEVER logs a prompt, a transcript,
// a reply or the key -- only a status code and an attempt count.
export interface ChatCompletionRequest {
  model: string;
  messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }>;
  temperature: number;
  max_tokens: number;
  response_format: Record<string, unknown>;
}

export interface ChatCompletionUsage { prompt_tokens?: number; completion_tokens?: number; prompt_tokens_details?: { cached_tokens?: number } }

export interface ChatCompletionResult {
  /** The assistant message content (a JSON string under structured output), or null on refusal / empty. */
  content: string | null;
  refusal: boolean;
  usage: ChatCompletionUsage;
  status: number;
  attempts: number;
}

export interface ClientOptions {
  apiKey: string;
  baseUrl: string;               // e.g. https://api.openai.com/v1 (no trailing slash)
  fetchImpl: typeof fetch;
  attemptTimeoutMs: number;
  extraHeaders?: Record<string, string>;
}

export class ProviderHttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const RETRYABLE = new Set([408, 409, 425, 429, 500, 502, 503, 504]);

export async function chatCompletions(opts: ClientOptions, body: ChatCompletionRequest, signal: AbortSignal): Promise<ChatCompletionResult> {
  let lastError: unknown = null;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    if (signal.aborted) throw abortError(signal);
    const ac = new AbortController();
    const onAbort = () => ac.abort(signal.reason);
    signal.addEventListener('abort', onAbort, { once: true });
    const timer = setTimeout(() => ac.abort(new Error('attempt_timeout')), opts.attemptTimeoutMs);
    try {
      const res = await opts.fetchImpl(`${opts.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${opts.apiKey}`, ...(opts.extraHeaders ?? {}) },
        body: JSON.stringify(body),
        signal: ac.signal,
      });
      if (!res.ok) {
        // Drain and drop the body: never logged, never parsed for text.
        await res.text().catch(() => '');
        const err = new ProviderHttpError(res.status, `provider http ${res.status}`);
        if (RETRYABLE.has(res.status) && attempt === 1 && !signal.aborted) {
          lastError = err;
          continue;
        }
        throw err;
      }
      const json = (await res.json()) as { choices?: Array<{ message?: { content?: string | null; refusal?: string | null } }>; usage?: ChatCompletionUsage };
      const message = json.choices?.[0]?.message;
      const refusal = Boolean(message?.refusal);
      const content = !refusal && typeof message?.content === 'string' && message.content.length ? message.content : null;
      return { content, refusal, usage: json.usage ?? {}, status: res.status, attempts: attempt };
    } catch (err) {
      if (signal.aborted) throw abortError(signal);
      const timedOut = ac.signal.aborted;
      const transient = timedOut || err instanceof TypeError || (err instanceof ProviderHttpError && RETRYABLE.has(err.status));
      if (transient && attempt === 1) {
        lastError = err;
        continue;
      }
      throw err instanceof ProviderHttpError ? err : new ProviderHttpError(timedOut ? 504 : 502, timedOut ? 'provider attempt timed out' : 'provider network error');
    } finally {
      clearTimeout(timer);
      signal.removeEventListener('abort', onAbort);
    }
  }
  const e = lastError;
  throw e instanceof ProviderHttpError ? e : new ProviderHttpError(504, 'provider attempts exhausted');
}

function abortError(signal: AbortSignal): Error {
  const reason = signal.reason;
  return reason instanceof Error ? reason : new Error(typeof reason === 'string' ? reason : 'aborted');
}
