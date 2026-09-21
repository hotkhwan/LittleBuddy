// Server-side lesson authority. The Worker resolves stepId itself so the only
// free text a device can put in front of a model is the child's transcript.
import { LESSON_ACTIONS } from './turn_validator';
import type { LessonContext, Outcome } from './types';
import { RAW_LESSONS } from './content';

export interface LessonStep {
  stepId: string;
  kind: 'ask' | 'teach' | 'celebrate' | 'choose';
  questionText: string;
  teachText: string;
  visualAssetId: string;
  expectedAnswers: string[];
  hint: string;
  encouragement: string;
  successLine: string;
  answerLine: string;
}
export interface Lesson { lessonId: string; title: string; steps: LessonStep[] }

function strOr(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

export function parseLesson(raw: unknown): Lesson | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const lessonId = typeof r.lessonId === 'string' ? r.lessonId : '';
  if (!lessonId || !Array.isArray(r.steps) || r.steps.length === 0) return null;
  const steps: LessonStep[] = [];
  for (const s of r.steps as Record<string, unknown>[]) {
    if (!s || typeof s.stepId !== 'string') return null;
    const kind = ['ask', 'teach', 'celebrate', 'choose'].includes(s.kind as string) ? (s.kind as LessonStep['kind']) : 'teach';
    steps.push({
      stepId: s.stepId,
      kind,
      questionText: strOr(s.questionText),
      teachText: strOr(s.teachText),
      visualAssetId: strOr(s.visualAssetId),
      expectedAnswers: Array.isArray(s.expectedAnswers) ? (s.expectedAnswers as unknown[]).filter((a): a is string => typeof a === 'string') : [],
      hint: strOr(s.hint),
      encouragement: strOr(s.encouragement),
      successLine: strOr(s.successLine),
      answerLine: strOr(s.answerLine),
    });
  }
  return { lessonId, title: strOr(r.title), steps };
}

export const LESSONS: ReadonlyMap<string, Lesson> = new Map(
  RAW_LESSONS.map(parseLesson).filter((l): l is Lesson => l !== null).map((l) => [l.lessonId, l]),
);

function nextText(lesson: Lesson, index: number): { text: string; isEnd: boolean } {
  const next = lesson.steps[index + 1];
  if (!next) return { text: '', isEnd: true };
  if (next.kind === 'ask' || next.kind === 'choose') return { text: next.questionText || next.teachText, isEnd: false };
  if (next.kind === 'celebrate') return { text: next.teachText, isEnd: true };
  return { text: next.teachText || next.questionText, isEnd: false };
}

/** Trusted lesson context for a turn; only outcome/stepId/matched/lessonAction come from the client. */
export function resolveLessonContext(lesson: Lesson, client: { stepId: string; outcome: Outcome; matched?: string; lessonAction?: string }): LessonContext | null {
  const index = lesson.steps.findIndex((s) => s.stepId === client.stepId);
  if (index < 0) return null;
  const step = lesson.steps[index];
  const next = nextText(lesson, index);
  const expected = step.expectedAnswers;
  const matchedRaw = (client.matched ?? '').trim().toLowerCase();
  const matched = expected.find((a) => a.toLowerCase() === matchedRaw) ?? '';
  const clientAction = LESSON_ACTIONS.includes((client.lessonAction ?? '') as never) ? client.lessonAction! : '';

  let lessonAction: string;
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
