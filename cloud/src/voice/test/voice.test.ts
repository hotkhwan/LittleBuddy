import { describe, expect, it } from 'vitest';
import { VoiceFallbackMachine } from '../fallback';
import { parseClientEvent, safeVoiceError } from '../protocol';
import { VoiceTurnTimer } from '../turn_metrics';
import { assertVoiceRuntimeAllowed } from '../types';

describe('voice protocol', () => {
  it('accepts only bounded, typed client control events', () => {
    expect(parseClientEvent('{"type":"audio.start","turnId":"t1","format":"pcm16","sampleRate":16000}')).toEqual({ type: 'audio.start', turnId: 't1', format: 'pcm16', sampleRate: 16000 });
    expect(parseClientEvent('{"type":"audio.start","turnId":"t1","format":"mp3","sampleRate":16000}')).toBeNull();
    expect(parseClientEvent('{"type":"unknown"}')).toBeNull();
    expect(parseClientEvent('x'.repeat(4097))).toBeNull();
  });

  it('never exposes infrastructure detail to the child', () => {
    expect(safeVoiceError('HTTP 500 api key leaked')).toEqual({ type: 'error', code: 'provider_unavailable', retryable: false, childMessage: "Let's keep learning another way." });
  });
});

describe('voice launch gate', () => {
  it('keeps child audio disabled without both flag and consent', () => {
    expect(() => assertVoiceRuntimeAllowed({ liveChildAudioEnabled: false, consentGranted: true, syntheticOrAdultQa: false })).toThrow(/not available/);
    expect(() => assertVoiceRuntimeAllowed({ liveChildAudioEnabled: true, consentGranted: false, syntheticOrAdultQa: false })).toThrow(/not available/);
    expect(() => assertVoiceRuntimeAllowed({ liveChildAudioEnabled: false, consentGranted: false, syntheticOrAdultQa: true })).not.toThrow();
  });
});

describe('fallback and metrics', () => {
  it('degrades premium to standard to local without looping', () => {
    const f = new VoiceFallbackMachine(new Set(['cloudflare', 'standard', 'local']));
    expect(f.current()).toBe('cloudflare');
    expect(f.fail('provider_unavailable')).toMatchObject({ from: 'cloudflare', to: 'standard' });
    expect(f.fail('quota_exhausted')).toMatchObject({ from: 'standard', to: 'local' });
    expect(f.fail('provider_unavailable')).toBeNull();
  });

  it('records timing only, never audio or transcript content', () => {
    let now = 100;
    const timer = new VoiceTurnTimer('turn-1', () => now);
    timer.mark('stt', 31.4); timer.mark('llm', 42.6); now = 250;
    expect(timer.finish({ inputAudioMs: 500 })).toEqual({ turnId: 'turn-1', sttMs: 31, llmMs: 43, ttsMs: undefined, totalMs: 150, inputAudioMs: 500 });
  });
});

