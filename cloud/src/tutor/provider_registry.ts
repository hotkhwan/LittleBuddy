// Which TutorProvider serves a request. Decided from config in the Worker
// (so tests can override it through the app factory) and instantiated where
// it is used (Worker route for realtime minting, TutorSessionDO for turns).
import type { Config } from '../env';
import { ASSET_ALLOWLIST } from './content';
import { createFaultyProvider, createMockProvider } from './mock_provider';
import { isTutorProvider, type ProviderFactory, type TutorProvider } from './provider_interface';

// ---------------------------------------------------------------------------
// Agent E: replace `null` with your factory, e.g.
//   import { createOpenAIProvider } from './provider/index';
//   const OPENAI_FACTORY: ProviderFactory | null = createOpenAIProvider;
// Nothing else in the Worker changes.
// ---------------------------------------------------------------------------
const OPENAI_FACTORY: ProviderFactory | null = null;

export function openAiFactoryWired(): boolean {
  return OPENAI_FACTORY !== null;
}

export function resolveProvider(config: Config, apiKey: string | undefined, fetchImpl?: typeof fetch): TutorProvider {
  if (config.providerName === 'faulty') return createFaultyProvider();
  if (config.providerName === 'openai' && apiKey && OPENAI_FACTORY) {
    const p = OPENAI_FACTORY({ apiKey, model: config.model, realtimeModel: config.realtimeModel, realtimeVoice: config.realtimeVoice, fetchImpl });
    if (isTutorProvider(p)) return p;
  }
  return createMockProvider({ allowlist: ASSET_ALLOWLIST.ids });
}
