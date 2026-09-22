import { Agent } from 'agents';
import { withVoice, WorkersAIFluxSTT, WorkersAITTS, type VoiceTurnContext } from '@cloudflare/voice';

const VoiceBase = withVoice(Agent, { historyLimit: 4, maxMessageCount: 8, audioFormat: 'mp3' });

/** Cloudflare Voice Beta prototype. The production gate rejects every call until legal approval. */
export class AlizVoiceAgent extends VoiceBase<Cloudflare.Env> {
  transcriber = new WorkersAIFluxSTT(this.env.AI, { eotThreshold: 0.75, keyterms: ['Aliz', 'Little Days'] });
  tts = new WorkersAITTS(this.env.AI, { speaker: 'asteria' });

  beforeCallStart(): boolean {
    return this.env.LIVE_CHILD_AUDIO_ENABLED === 'true' || this.env.LIVE_CHILD_AUDIO_ENABLED === '1';
  }

  async onTurn(transcript: string, context: VoiceTurnContext): Promise<string> {
    if (context.signal.aborted) return '';
    const normalized = transcript.trim().slice(0, 240);
    if (!normalized) return 'I am listening. Try again when you are ready.';
    return 'Nice speaking! Let us keep learning together.';
  }

  // Voice Beta persists history by default. Little Days deliberately disables
  // transcript persistence; only numeric turn metrics may leave the call.
  saveMessage(_role: 'user' | 'assistant', _text: string): void {}
}
