// Which TutorProvider serves a request. Decided from config in the Worker
// (so tests can override it through the app factory) and instantiated where
// it is used (Worker route for realtime minting, TutorSessionDO for turns).
//
// Merged 2026-09-22: Codex's Workers AI routed provider (`workers_ai`, the
// `AI` binding) and Claude's OpenAI turns factory (`openai`, OPENAI_API_KEY)
// live side by side. Without either the deterministic mock serves every turn
// and the realtime token route stays 503.
import type { Config } from '../env';
import { ASSET_ALLOWLIST } from './content';
import { createFaultyProvider, createMockProvider } from './mock_provider';
import { isTutorProvider, type ProviderFactory, type TutorProvider } from './provider_interface';
import { createOpenAIProvider, type OpenAIFactoryExtras } from './provider/openai/index';
import { createWorkersAIRoutedTurnProvider, type WorkersAIBinding } from './workers_ai_provider';

const OPENAI_FACTORY: ProviderFactory | null = createOpenAIProvider;

export function openAiFactoryWired(): boolean {
  return OPENAI_FACTORY !== null;
}

/** Fourth argument of `resolveProvider`: the Workers AI binding, or OpenAI extras. */
export type ProviderExtras = OpenAIFactoryExtras & { baseUrl?: string; ai?: WorkersAIBinding };

/**
 * Test seam for the Durable Object path, which cannot receive an injected
 * fetch or key through `createApp()`. Set by tests only; production never
 * calls it. `null` clears it.
 */
let testSeam: { fetchImpl?: typeof fetch; apiKey?: string; baseUrl?: string } | null = null;
export function setProviderTestSeam(seam: typeof testSeam): void {
  testSeam = seam;
}

function isAiBinding(value: unknown): value is WorkersAIBinding {
  return typeof value === 'object' && value !== null && typeof (value as { run?: unknown }).run === 'function';
}

export function resolveProvider(
  config: Config,
  apiKey: string | undefined,
  fetchImpl?: typeof fetch,
  extrasOrAi: ProviderExtras | WorkersAIBinding | undefined = {},
): TutorProvider {
  if (config.providerName === 'faulty') return createFaultyProvider();
  const extras: ProviderExtras = isAiBinding(extrasOrAi) ? { ai: extrasOrAi } : (extrasOrAi ?? {});
  const ai = extras.ai;
  if (config.providerName === 'workers_ai' && ai) {
    const turns = createWorkersAIRoutedTurnProvider({
      ai,
      primaryModel: config.standardPrimaryModel,
      fallbackModel: config.standardFallbackModel,
      reasoningModel: config.complexReasoningModel,
      timeoutMs: config.providerTimeoutMs,
      gateway: { id: 'default', skipCache: true },
    });
    return { name: turns.name, turns, realtime: null };
  }
  const key = apiKey || testSeam?.apiKey;
  const wantsOpenAi = config.providerName === 'openai' || Boolean(testSeam?.apiKey);
  if (wantsOpenAi && key && OPENAI_FACTORY) {
    const { baseUrl, ai: _ai, ...factoryExtras } = extras;
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
