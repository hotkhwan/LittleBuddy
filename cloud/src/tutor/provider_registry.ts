// Which TutorProvider serves a request. Decided from config in the Worker
// (so tests can override it through the app factory) and instantiated where
// it is used (Worker route for realtime minting, TutorSessionDO for turns).
import type { Config } from '../env';
import { ASSET_ALLOWLIST } from './content';
import { createFaultyProvider, createMockProvider } from './mock_provider';
import { isTutorProvider, type ProviderFactory, type TutorProvider } from './provider_interface';
import { createOpenAIProvider, type OpenAIFactoryExtras } from './provider/openai/index';

// ---------------------------------------------------------------------------
// Agent E / T2: the OpenAI factory (turns path; realtime stays null). It is
// instantiated ONLY when OPENAI_API_KEY is set; without the secret the
// deterministic mock serves every turn and the realtime token route is 503.
// ---------------------------------------------------------------------------
const OPENAI_FACTORY: ProviderFactory | null = createOpenAIProvider;

export function openAiFactoryWired(): boolean {
  return OPENAI_FACTORY !== null;
}

export type ProviderExtras = OpenAIFactoryExtras & { baseUrl?: string };

/**
 * Test seam for the Durable Object path, which cannot receive an injected
 * fetch or key through `createApp()`. Set by tests only; production never
 * calls it. `null` clears it.
 */
let testSeam: { fetchImpl?: typeof fetch; apiKey?: string; baseUrl?: string } | null = null;
export function setProviderTestSeam(seam: typeof testSeam): void {
  testSeam = seam;
}

export function resolveProvider(config: Config, apiKey: string | undefined, fetchImpl?: typeof fetch, extras: ProviderExtras = {}): TutorProvider {
  if (config.providerName === 'faulty') return createFaultyProvider();
  const key = apiKey || testSeam?.apiKey;
  const wantsOpenAi = config.providerName === 'openai' || Boolean(testSeam?.apiKey);
  if (wantsOpenAi && key && OPENAI_FACTORY) {
    const { baseUrl, ...factoryExtras } = extras;
    const p = OPENAI_FACTORY({
      apiKey: key,
      baseUrl: baseUrl || testSeam?.baseUrl,
      model: config.model,
      realtimeModel: config.realtimeModel,
      realtimeVoice: config.realtimeVoice,
      fetchImpl: fetchImpl ?? testSeam?.fetchImpl,
      ...factoryExtras,
    } as Parameters<ProviderFactory>[0]);
    if (isTutorProvider(p)) return p;
  }
  return createMockProvider({ allowlist: ASSET_ALLOWLIST.ids });
}
