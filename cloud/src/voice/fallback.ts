import type { VoiceFailureReason, VoiceProviderKind, VoiceServerEvent } from './types';

export const VOICE_FALLBACK_ORDER: readonly VoiceProviderKind[] = ['cloudflare', 'gemini', 'standard', 'local'];

export class VoiceFallbackMachine {
  private index = 0;
  constructor(private readonly available: ReadonlySet<VoiceProviderKind>, preferred: VoiceProviderKind = 'cloudflare') {
    const preferredIndex = VOICE_FALLBACK_ORDER.indexOf(preferred);
    this.index = preferredIndex < 0 ? 0 : preferredIndex;
    while (this.index < VOICE_FALLBACK_ORDER.length - 1 && !available.has(VOICE_FALLBACK_ORDER[this.index])) this.index += 1;
  }

  current(): VoiceProviderKind { return this.available.has(VOICE_FALLBACK_ORDER[this.index]) ? VOICE_FALLBACK_ORDER[this.index] : 'local'; }

  fail(reason: VoiceFailureReason): VoiceServerEvent | null {
    const from = this.current();
    for (let next = this.index + 1; next < VOICE_FALLBACK_ORDER.length; next += 1) {
      if (!this.available.has(VOICE_FALLBACK_ORDER[next])) continue;
      this.index = next;
      return { type: 'fallback', from, to: this.current(), reason };
    }
    return null;
  }
}

