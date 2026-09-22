import type { VoiceTurnMetrics } from './types';

/** Aggregate numeric timing only. This intentionally accepts no transcript or audio. */
export class VoiceTurnTimer {
  private readonly startedAt: number;
  private marks = new Map<'stt' | 'llm' | 'tts', number>();
  constructor(readonly turnId: string, private readonly clock: () => number = () => performance.now()) { this.startedAt = clock(); }
  mark(stage: 'stt' | 'llm' | 'tts', elapsedMs: number): void { this.marks.set(stage, Math.max(0, Math.round(elapsedMs))); }
  finish(audio: { inputAudioMs?: number; outputAudioMs?: number } = {}): VoiceTurnMetrics {
    return { turnId: this.turnId, sttMs: this.marks.get('stt'), llmMs: this.marks.get('llm'), ttsMs: this.marks.get('tts'), totalMs: Math.max(0, Math.round(this.clock() - this.startedAt)), ...audio };
  }
}

