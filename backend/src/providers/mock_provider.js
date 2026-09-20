// MockConversationProvider: deterministic, offline, no network. Builds the
// TutorTurn from the lesson context the client already computed with its
// LessonEngine (outcome, next question, hint). A full lesson runs end to end
// against this provider, and it is also the fallback when a real provider
// times out or fails.
import { MAX_NEXT_QUESTION, MAX_SPEECH } from '../turn_validator.js';

const PRAISE = ['Great!', 'Nice!', 'Yes!', 'Well done!', 'Super!'];
const ENCOURAGE = ["Let's try together!", 'Nice try!', 'Almost!', 'Good listening!'];

/**
 * @param {{allowlist?: readonly string[]}} [opts]
 * @returns {import('../types.js').ConversationProvider}
 */
export function createMockProvider(opts = {}) {
  const allowlist = new Set(opts.allowlist ?? []);

  return {
    name: 'mock',
    async generateTurn({ lessonContext, transcript }) {
      const ctx = lessonContext ?? {};
      const outcome = ctx.outcome;
      const seed = hash(`${ctx.stepId}|${outcome}|${transcript ?? ''}`);
      const answer = firstString(ctx.matched) || firstString(ctx.expectedAnswers?.[0]) || '';
      const next = firstString(ctx.nextQuestionText);
      const hint = firstString(ctx.hint);
      const visual = ctx.visualAssetId && (allowlist.size === 0 || allowlist.has(ctx.visualAssetId))
        ? { type: 'flashcard', assetId: ctx.visualAssetId }
        : { type: 'none' };

      /** @type {Record<string, unknown>} */
      let turn;
      if (outcome === 'correct') {
        const praise = PRAISE[seed % PRAISE.length];
        const echo = answer ? ` ${cap(answer)}!` : '';
        if (next) {
          turn = { speech: clip(`${praise}${echo} ${next}`, MAX_SPEECH), emotion: 'happy', gesture: 'clap', visual, lessonAction: 'next_question', nextQuestion: clip(next, MAX_NEXT_QUESTION) };
        } else {
          turn = { speech: clip(`${praise}${echo} You did the whole lesson. Great job today!`, MAX_SPEECH), emotion: 'happy', gesture: 'wave', visual, lessonAction: ctx.lessonAction === 'end_session' ? 'end_session' : 'complete' };
        }
      } else if (outcome === 'incorrect') {
        const enc = ENCOURAGE[seed % ENCOURAGE.length];
        if (hint) {
          turn = { speech: clip(`${enc} ${hint}`, MAX_SPEECH), emotion: 'encouraging', gesture: 'point', visual, lessonAction: 'give_hint' };
        } else {
          turn = { speech: clip(`${enc} Listen again. Can you say it with me?`, MAX_SPEECH), emotion: 'encouraging', gesture: 'tilt', visual, lessonAction: 'retry' };
        }
      } else {
        // unclear (or unknown outcome): never a fail state; move gently on.
        if (ctx.lessonAction === 'next_question' && next) {
          turn = { speech: clip(`Good try! The word is ${answer || 'this one'}. ${next}`, MAX_SPEECH), emotion: 'smile', gesture: 'nod', visual, lessonAction: 'next_question', nextQuestion: clip(next, MAX_NEXT_QUESTION) };
        } else {
          turn = { speech: clip(`I did not quite hear you. ${hint || 'Can you say it one more time?'}`, MAX_SPEECH), emotion: 'listening', gesture: 'tilt', visual, lessonAction: 'retry' };
        }
      }
      turn.subtitle = turn.speech;
      return { turn, usage: { llmInputTokens: 0, llmOutputTokens: 0 } };
    },
  };
}

/** @param {unknown} v */
function firstString(v) {
  return typeof v === 'string' ? v.trim() : '';
}
/** @param {string} s */
function cap(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
/** @param {string} s @param {number} max */
function clip(s, max) {
  const t = s.replace(/\s+/g, ' ').trim();
  if (t.length <= max) return t;
  const cut = t.slice(0, max - 1);
  const lastSpace = cut.lastIndexOf(' ');
  return `${cut.slice(0, lastSpace > max / 2 ? lastSpace : max - 1).replace(/[,;:\s]+$/, '')}.`;
}
/** @param {string} s */
function hash(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}
