export type VoiceProviderKind = 'cloudflare' | 'gemini' | 'standard' | 'local';

export interface VoiceTurnMetrics {
  turnId: string;
  sttMs?: number;
  llmMs?: number;
  ttsMs?: number;
  totalMs?: number;
  inputAudioMs?: number;
  outputAudioMs?: number;
}

export type VoiceServerEvent =
  | { type: 'session.ready'; sessionId: string; provider: VoiceProviderKind }
  | { type: 'transcript.partial'; turnId: string; text: string }
  | { type: 'transcript.final'; turnId: string; text: string }
  | { type: 'assistant.text'; turnId: string; text: string }
  | { type: 'assistant.audio'; turnId: string; format: 'pcm16'; sampleRate: number }
  | { type: 'turn.metrics'; metrics: VoiceTurnMetrics }
  | { type: 'turn.cancelled'; turnId: string }
  | { type: 'fallback'; from: VoiceProviderKind; to: VoiceProviderKind; reason: VoiceFailureReason }
  | { type: 'error'; code: VoiceFailureReason; retryable: boolean; childMessage: string };

export type VoiceClientEvent =
  | { type: 'session.start'; sessionId: string; locale: string }
  | { type: 'audio.start'; turnId: string; format: 'pcm16'; sampleRate: number }
  | { type: 'audio.end'; turnId: string }
  | { type: 'turn.interrupt'; turnId: string }
  | { type: 'turn.cancel'; turnId: string }
  | { type: 'session.end'; sessionId: string };

export type VoiceFailureReason =
  | 'disabled'
  | 'quota_exhausted'
  | 'provider_unavailable'
  | 'stt_failed'
  | 'tts_failed'
  | 'timeout'
  | 'disconnected'
  | 'invalid_event';

export interface SttResult { text: string; confidence?: number; latencyMs: number }
export interface TtsResult { audio: ArrayBuffer; format: 'pcm16'; sampleRate: number; latencyMs: number }

export interface SttAdapter {
  readonly name: string;
  transcribe(audio: ArrayBuffer, options: { locale: string; signal: AbortSignal }): Promise<SttResult>;
}

export interface TtsAdapter {
  readonly name: string;
  synthesize(text: string, options: { locale: string; voice?: string; signal: AbortSignal }): Promise<TtsResult>;
}

export interface VoiceRuntimeGate {
  liveChildAudioEnabled: boolean;
  consentGranted: boolean;
  syntheticOrAdultQa: boolean;
}

export function assertVoiceRuntimeAllowed(gate: VoiceRuntimeGate): void {
  // Synthetic/adult QA is intentionally independent of the child-audio launch gate.
  if (gate.syntheticOrAdultQa) return;
  if (!gate.liveChildAudioEnabled || !gate.consentGranted) {
    throw Object.assign(new Error('Live voice is not available.'), { code: 'disabled' as const });
  }
}

