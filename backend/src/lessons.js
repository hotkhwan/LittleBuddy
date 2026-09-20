// Server-side lesson authority (security finding M2). The backend loads the
// same lesson files the game ships (game/content/tutor/lessons/*.json, path
// via LESSONS_DIR) and resolves stepId itself, so the only free text a device
// can put in front of the model is the child's transcript. Client-supplied
// hint / nextQuestionText / expectedAnswers are ignored for known lessons.
import fs from 'node:fs';
import path from 'node:path';
import { LESSON_ACTIONS } from './turn_validator.js';

/**
 * @typedef {{stepId: string, kind: 'ask'|'teach'|'celebrate', questionText?: string, teachText?: string, visualAssetId?: string, expectedAnswers?: string[], hint?: string, encouragement?: string, successLine?: string, answerLine?: string}} LessonStep
 * @typedef {{lessonId: string, title?: string, steps: LessonStep[]}} Lesson
 */

/**
 * @param {string} dir
 * @returns {{lessons: Map<string, Lesson>, source: 'dir'|'none', errors: string[]}}
 */
export function loadLessons(dir) {
  /** @type {Map<string, Lesson>} */
  const lessons = new Map();
  const errors = [];
  let entries = [];
  try {
    entries = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
  } catch {
    return { lessons, source: 'none', errors: [`lessons dir not readable: ${dir}`] };
  }
  for (const file of entries) {
    try {
      const raw = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
      const lessonId = typeof raw.lessonId === 'string' ? raw.lessonId : path.basename(file, '.json');
      if (!Array.isArray(raw.steps) || raw.steps.length === 0) throw new Error('no steps');
      const steps = raw.steps.map((s, i) => {
        if (!s || typeof s.stepId !== 'string') throw new Error(`step ${i} has no stepId`);
        return {
          stepId: s.stepId,
          kind: ['ask', 'teach', 'celebrate'].includes(s.kind) ? s.kind : 'teach',
          questionText: strOr(s.questionText),
          teachText: strOr(s.teachText),
          visualAssetId: strOr(s.visualAssetId),
          expectedAnswers: Array.isArray(s.expectedAnswers) ? s.expectedAnswers.filter((a) => typeof a === 'string') : [],
          hint: strOr(s.hint),
          encouragement: strOr(s.encouragement),
          successLine: strOr(s.successLine),
          answerLine: strOr(s.answerLine),
        };
      });
      lessons.set(lessonId, { lessonId, title: strOr(raw.title), steps });
    } catch (err) {
      errors.push(`${file}: ${err?.message ?? err}`);
    }
  }
  return { lessons, source: 'dir', errors };
}

/**
 * The line Aliz says to move on from `step`: the next step's question (ask),
 * its teach text (teach) or its celebration text.
 * @param {Lesson} lesson
 * @param {number} index
 */
function nextText(lesson, index) {
  const next = lesson.steps[index + 1];
  if (!next) return { text: '', isEnd: true };
  if (next.kind === 'ask') return { text: next.questionText || next.teachText, isEnd: false };
  if (next.kind === 'celebrate') return { text: next.teachText, isEnd: true };
  return { text: next.teachText || next.questionText, isEnd: false };
}

/**
 * Build the trusted lesson context for a turn from the lesson file. Only
 * `outcome`, `stepId`, `matched` (if it is an expected answer) and a
 * plausibility-checked `lessonAction` come from the client.
 * @param {Lesson} lesson
 * @param {{stepId: string, outcome: 'correct'|'incorrect'|'unclear', matched?: string, lessonAction?: string}} client
 * @returns {import('./types.js').LessonContext | null} null when stepId is unknown
 */
export function resolveLessonContext(lesson, client) {
  const index = lesson.steps.findIndex((s) => s.stepId === client.stepId);
  if (index < 0) return null;
  const step = lesson.steps[index];
  const next = nextText(lesson, index);
  const expected = step.expectedAnswers ?? [];
  const matchedRaw = (client.matched ?? '').trim().toLowerCase();
  const matched = expected.find((a) => a.toLowerCase() === matchedRaw) ?? '';
  const clientAction = LESSON_ACTIONS.includes(client.lessonAction ?? '') ? client.lessonAction : '';

  let lessonAction;
  if (client.outcome === 'correct') lessonAction = next.isEnd ? (clientAction === 'end_session' ? 'end_session' : 'complete') : 'next_question';
  else if (client.outcome === 'incorrect') lessonAction = clientAction === 'give_hint' && step.hint ? 'give_hint' : clientAction === 'retry' ? 'retry' : step.hint ? 'give_hint' : 'retry';
  else lessonAction = clientAction === 'next_question' ? (next.isEnd ? 'complete' : 'next_question') : clientAction === 'give_hint' && step.hint ? 'give_hint' : 'retry';

  return {
    stepId: step.stepId,
    outcome: client.outcome,
    expectedAnswers: expected,
    hint: step.hint,
    nextQuestionText: next.text,
    visualAssetId: step.visualAssetId,
    matched,
    lessonAction,
    successLine: step.successLine,
    answerLine: step.answerLine,
    encouragement: step.encouragement,
    isLastStep: next.isEnd,
  };
}

/** @param {unknown} v */
function strOr(v) {
  return typeof v === 'string' ? v.trim() : '';
}
