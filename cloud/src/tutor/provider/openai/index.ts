// Agent E / T2: the OpenAI ProviderFactory for the TURNS path (lesson turns
// and free-chat turns). Wired in provider_registry.ts; it only ever runs when
// OPENAI_API_KEY is set on the Worker (a Worker Secret), never from a client.
//
// `realtime` is null on purpose: minting ephemeral Realtime tokens is not part
// of this module yet, so POST /v1/tutor/realtime/token keeps answering 503
// provider_unavailable even with a key. The turns path is what free chat uses.
import type { ProviderFactory, ProviderFactoryOptions, TutorProvider } from '../../provider_interface';
import { ASSET_ALLOWLIST } from '../../content';
import { DEFAULT_MAX_OUTPUT_TOKENS, DEFAULT_TEMPERATURE, createOpenAITurnProvider } from './turns';

export const DEFAULT_OPENAI_BASE_URL = 'https://api.openai.com/v1';
/** Per-attempt timeout; the session DO's providerTimeoutMs (default 6000) bounds the whole call. */
export const DEFAULT_ATTEMPT_TIMEOUT_MS = 4000;

export interface OpenAIFactoryExtras {
  maxOutputTokens?: number;
  attemptTimeoutMs?: number;
  temperature?: number;
  assetIds?: readonly string[];
}

export const createOpenAIProvider: ProviderFactory = (opts: ProviderFactoryOptions & OpenAIFactoryExtras): TutorProvider => {
  const baseUrl = (opts.baseUrl || DEFAULT_OPENAI_BASE_URL).replace(/\/+$/, '');
  const turns = createOpenAITurnProvider({
    model: opts.model,
    assetIds: opts.assetIds ?? ASSET_ALLOWLIST.ids,
    temperature: opts.temperature ?? DEFAULT_TEMPERATURE,
    maxOutputTokens: opts.maxOutputTokens ?? DEFAULT_MAX_OUTPUT_TOKENS,
    client: {
      apiKey: opts.apiKey,
      baseUrl,
      fetchImpl: opts.fetchImpl ?? fetch,
      attemptTimeoutMs: opts.attemptTimeoutMs ?? DEFAULT_ATTEMPT_TIMEOUT_MS,
      extraHeaders: opts.extraHeaders,
    },
  });
  return { name: turns.name, turns, realtime: null };
};
