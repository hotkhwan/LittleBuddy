import corpus from '../../curriculum/english/corpus.json';
import { ENABLED_LANGUAGES, ENABLED_SUBJECTS, type CurriculumLesson } from './types';

const ID_RE = /^[a-z0-9][a-z0-9_-]{2,79}$/;
const PROMPT_INJECTION = /\b(?:ignore|override|reveal|repeat)\b.{0,60}\b(?:system|developer|previous instructions?|prompt)\b|<\/?(?:system|assistant|tool)>|\b(?:system|developer)\s*:/i;

export function validateCurriculumLesson(value: unknown): string[] {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return ['lesson:not_object'];
  const lesson = value as Partial<CurriculumLesson>;
  const errors: string[] = [];
  if (typeof lesson.id !== 'string' || !ID_RE.test(lesson.id)) errors.push('id:invalid');
  if (!Number.isInteger(lesson.version) || (lesson.version ?? 0) < 1) errors.push('version:invalid');
  if (typeof lesson.publishedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(lesson.publishedAt)) errors.push('publishedAt:invalid');
  if (lesson.active !== true && lesson.active !== false) errors.push('active:invalid');
  if (!ENABLED_LANGUAGES.includes(lesson.language as 'en')) errors.push('language:not_enabled');
  if (!ENABLED_SUBJECTS.includes(lesson.subject as 'english')) errors.push('subject:not_enabled');
  for (const key of ['ageBand', 'grade', 'skill', 'difficulty', 'lessonType', 'learningStandard', 'learningObjective', 'activityRecommendation', 'content'] as const) {
    if (typeof lesson[key] !== 'string' || !(lesson[key] as string).trim()) errors.push(`${key}:required`);
  }
  for (const key of ['prerequisites', 'targetVocabulary', 'teacherPrompts', 'expectedResponses', 'hints', 'successCriteria', 'commonMistakes', 'learningProps', 'difficultyVariants'] as const) {
    if (!Array.isArray(lesson[key]) || lesson[key]!.length === 0) errors.push(`${key}:required`);
  }
  if (!Number.isInteger(lesson.durationMinutes) || (lesson.durationMinutes ?? 0) < 1 || (lesson.durationMinutes ?? 99) > 15) errors.push('durationMinutes:invalid');
  const serialized = JSON.stringify(value);
  if (PROMPT_INJECTION.test(serialized)) errors.push('content:prompt_injection');
  return errors;
}

function loadCorpus(): readonly CurriculumLesson[] {
  if (!Array.isArray(corpus)) throw new Error('Curriculum corpus must be an array.');
  const ids = new Set<string>();
  return Object.freeze(corpus.map((raw) => {
    const errors = validateCurriculumLesson(raw);
    if (errors.length) throw new Error(`Invalid curriculum ${String((raw as { id?: unknown }).id)}: ${errors.join(',')}`);
    const lesson = structuredClone(raw) as CurriculumLesson;
    if (ids.has(lesson.id)) throw new Error(`Duplicate curriculum id: ${lesson.id}`);
    ids.add(lesson.id);
    return deepFreeze(lesson);
  }));
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    Object.freeze(value);
    for (const child of Object.values(value as Record<string, unknown>)) deepFreeze(child);
  }
  return value;
}

export const CURRICULUM = loadCorpus();
export const CURRICULUM_BY_ID = new Map(CURRICULUM.map((lesson) => [lesson.id, lesson]));
