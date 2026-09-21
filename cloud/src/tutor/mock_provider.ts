// Deterministic, offline provider: builds the TutorTurn from the trusted
// lesson context. A full lesson runs end to end against it, and it is the
// fallback whenever a real provider times out, errors or answers unsafely.
import { MAX_NEXT_QUESTION, MAX_SPEECH } from './turn_validator';
import type { ProviderTurnResult, TurnInput, TurnProvider, TutorProvider } from './provider_interface';

const PRAISE = ['Great!', 'Nice!', 'Yes!', 'Well done!', 'Super!'];
const ENCOURAGE = ["Let's try together!", 'Nice try!', 'Almost!', 'Good listening!'];

export function createMockTurnProvider(opts: { allowlist?: readonly string[] } = {}): TurnProvider {
  const allowlist = new Set(opts.allowlist ?? []);
  return {
    name: 'mock',
    async generateTurn({ lessonContext, transcript }: TurnInput): Promise<ProviderTurnResult> {
      const ctx = lessonContext;
      const outcome = ctx.outcome;
      const seed = hash(`${ctx.stepId}|${outcome}|${transcript ?? ''}`);
      const answer = firstString(ctx.matched) || firstString(ctx.expectedAnswers?.[0]) || '';
      const next = firstString(ctx.nextQuestionText);
      const hint = firstString(ctx.hint);
      const visual = ctx.visualAssetId && (allowlist.size === 0 || allowlist.has(ctx.visualAssetId))
        ? { type: 'flashcard', assetId: ctx.visualAssetId }
        : { type: 'none' };

      let turn: Record<string, unknown>;
      const successLine = firstString(ctx.successLine);
      const answerLine = firstString(ctx.answerLine);
      if (outcome === 'correct') {
        const praise = PRAISE[seed % PRAISE.length];
        const echo = successLine ? ` ${successLine}` : answer ? ` ${cap(answer)}!` : '';
        const finishing = !next || ctx.lessonAction === 'complete' || ctx.lessonAction === 'end_session';
        if (!finishing) {
          turn = { speech: clip(`${praise}${echo} ${next}`, MAX_SPEECH), emotion: 'happy', gesture: 'clap', visual, lessonAction: 'next_question', nextQuestion: clip(next, MAX_NEXT_QUESTION) };
        } else {
          turn = { speech: clip(`${praise}${echo} ${next || 'You did the whole lesson. Great job today!'}`, MAX_SPEECH), emotion: 'happy', gesture: 'wave', visual, lessonAction: ctx.lessonAction === 'end_session' ? 'end_session' : 'complete' };
        }
      } else if (outcome === 'incorrect') {
        const enc = ENCOURAGE[seed % ENCOURAGE.length];
        if (hint) turn = { speech: clip(`${enc} ${hint}`, MAX_SPEECH), emotion: 'encouraging', gesture: 'point', visual, lessonAction: 'give_hint' };
        else turn = { speech: clip(`${enc} Listen again. Can you say it with me?`, MAX_SPEECH), emotion: 'encouraging', gesture: 'tilt', visual, lessonAction: 'retry' };
      } else if (ctx.lessonAction === 'next_question' && next) {
        turn = { speech: clip(`Good try! ${answerLine || `The word is ${answer || 'this one'}.`} ${next}`, MAX_SPEECH), emotion: 'smile', gesture: 'nod', visual, lessonAction: 'next_question', nextQuestion: clip(next, MAX_NEXT_QUESTION) };
      } else {
        turn = { speech: clip(`I did not quite hear you. ${hint || 'Can you say it one more time?'}`, MAX_SPEECH), emotion: 'listening', gesture: 'tilt', visual, lessonAction: 'retry' };
      }
      turn.subtitle = turn.speech;
      return { turn, usage: { llmInputTokens: 0, llmOutputTokens: 0 } };
    },
  };
}

export function createMockProvider(opts: { allowlist?: readonly string[] } = {}): TutorProvider {
  return { name: 'mock', turns: createMockTurnProvider(opts), realtime: null };
}

/** DEV_MODE chaos provider: unsafe text, so the validator must reject it and the mock must answer. */
export function createFaultyProvider(): TutorProvider {
  return {
    name: 'faulty',
    turns: {
      name: 'faulty',
      async generateTurn() {
        return { turn: { speech: 'Visit www.example.com now!!!', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'retry' }, usage: { llmInputTokens: 12, llmOutputTokens: 7 } };
      },
    },
    realtime: null,
  };
}

function firstString(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}
function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
function clip(s: string, max: number): string {
  const t = s.replace(/\s+/g, ' ').trim();
  if (t.length <= max) return t;
  const cut = t.slice(0, max - 1);
  const lastSpace = cut.lastIndexOf(' ');
  return `${cut.slice(0, lastSpace > max / 2 ? lastSpace : max - 1).replace(/[,;:\s]+$/, '')}.`;
}
function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}
