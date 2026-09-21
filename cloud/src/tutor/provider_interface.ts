// THE contract between the Worker (Agent D) and the provider module
// (Agent E, cloud/src/tutor/provider/**). The Worker never imports an SDK,
// never sees a vendor hostname outside the provider module, and treats every
// provider result as untrusted: turns go through validateTurn() and anything
// invalid becomes the safe fallback.
//
// Agent E implements `ProviderFactory` in cloud/src/tutor/provider/index.ts:
//
//   export const createOpenAIProvider: ProviderFactory = (opts) => ({ name, turns, realtime });
//
// and Agent D wires it in cloud/src/tutor/provider_registry.ts (one line,
// marked). Until then the registry resolves to the deterministic mock.
import type { LessonContext, TutorTurn } from './types';
import type { Lesson } from './lessons';

export interface TurnInput {
  transcript: string;          // <= 500 chars; the ONLY free text from the device
  lessonId: string;
  lessonContext: LessonContext; // server-resolved (trusted)
  signal: AbortSignal;          // aborted on timeout or client cancel; the provider must stop work
}

export interface TurnUsage {
  llmInputTokens: number;
  llmOutputTokens: number;
  cachedInputTokens?: number;
}

export interface ProviderTurnResult {
  turn: unknown;               // RAW candidate; the Worker validates it
  usage: TurnUsage;
}

export interface TurnProvider {
  readonly name: string;       // e.g. "openai:gpt-4o-mini"; appears in responses as `provider`
  generateTurn(input: TurnInput): Promise<ProviderTurnResult>;
}

export interface RealtimeMintInput {
  lesson: Lesson | null;       // server lesson (null only in DEV_MODE for an unknown lesson)
  instructions: string;        // server-built (buildRealtimeInstructions); never client text
  expiresSeconds: number;      // already clamped to 10..7200 = remaining quota + grace
  turnDetection: 'semantic_vad' | 'server_vad';
  voice: string;
  signal: AbortSignal;
}

export interface RealtimeMintResult {
  value: string;               // the ephemeral client secret (ek_...). Never logged, never stored.
  expiresAt: string;           // ISO 8601
  model: string;
  turnDetection: string;
  wsUrl: string;               // wss://... the game dials with the ephemeral secret
  subprotocols?: string[];     // e.g. ["realtime", "openai-insecure-api-key.<ek_...>"]
  headers?: string[];          // alternative to subprotocols
  sessionUpdate?: Record<string, unknown>; // first client event the game sends verbatim
}

export interface RealtimeTokenProvider {
  readonly name: string;
  readonly model: string;
  mint(input: RealtimeMintInput): Promise<RealtimeMintResult>;
}

export interface TutorProvider {
  readonly name: string;
  readonly turns: TurnProvider;
  readonly realtime: RealtimeTokenProvider | null; // null => POST /v1/tutor/realtime/token is 503 provider_unavailable
}

export interface ProviderFactoryOptions {
  apiKey: string;
  baseUrl?: string;
  model: string;
  realtimeModel: string;
  realtimeVoice: string;
  fetchImpl?: typeof fetch;    // tests inject a fake; production uses global fetch
  extraHeaders?: Record<string, string>;
}

export type ProviderFactory = (opts: ProviderFactoryOptions) => TutorProvider;

/** Type guard the registry applies to whatever a factory returns. */
export function isTutorProvider(v: unknown): v is TutorProvider {
  const p = v as TutorProvider;
  return Boolean(p) && typeof p.name === 'string' && Boolean(p.turns) && typeof p.turns.generateTurn === 'function' && (p.realtime === null || (Boolean(p.realtime) && typeof p.realtime.mint === 'function'));
}

export type { TutorTurn };
