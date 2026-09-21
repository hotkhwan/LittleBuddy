// TutorTurn validator: the server half of the shared contract in
// docs/ALIZ_TUTOR_CONTRACTS.md. Rule-for-rule port of the prototype's
// backend/src/turn_validator.js; the client validator
// (game/scripts/tutor/turn/tutor_turn.gd) applies the same rules and all three
// run game/content/tutor/turn_fixtures.json (cloud/test/validator.test.ts).
//
// Anything invalid -> the safe fallback turn. Never throws on bad input and
// never lets a provider-authored string through unchecked.
import type { Emotion, Gesture, LessonAction, TutorTurn, VisualType } from './types';

export const EMOTIONS: readonly Emotion[] = ['neutral', 'listening', 'thinking', 'happy', 'encouraging', 'smile'];
export const GESTURES: readonly Gesture[] = ['none', 'nod', 'tilt', 'point', 'clap', 'wave'];
export const VISUAL_TYPES: readonly VisualType[] = ['none', 'flashcard', 'model'];
export const LESSON_ACTIONS: readonly LessonAction[] = ['next_question', 'retry', 'give_hint', 'complete', 'end_session', 'switch_lesson', 'jump_step'];

export const MAX_SPEECH = 160;
export const MAX_SUBTITLE = 160;
export const MAX_NEXT_QUESTION = 120;
export const MAX_DIGIT_RUN = 20;

export const DEFAULT_ASSET_ALLOWLIST: readonly string[] = [
  'apple_red', 'banana_yellow', 'cat', 'dog', 'number_1', 'number_2', 'number_3',
  'color_blue', 'color_green', 'color_red', 'color_yellow', 'orange_orange', 'grapes_purple',
];

export const BANNED_WORDS: readonly string[] = [
  'kill', 'die', 'dead', 'death', 'murder', 'blood', 'gun', 'knife', 'shoot', 'stab', 'bomb',
  'hate', 'stupid', 'idiot', 'dumb', 'ugly', 'loser', 'shut up',
  'damn', 'hell', 'crap', 'sex', 'sexy', 'naked', 'drug', 'drugs', 'beer', 'wine', 'drunk',
  'password', 'credit card', 'phone number', 'home address', 'where do you live', 'last name',
];

export const FALLBACK_SPEECH = "Let's try together!";

export function fallbackTurn(): TutorTurn {
  return { speech: FALLBACK_SPEECH, subtitle: FALLBACK_SPEECH, emotion: 'encouraging', gesture: 'tilt', visual: { type: 'none' }, lessonAction: 'retry' };
}

const ASCII_PRINTABLE = /^[\x20-\x7E]*$/;
const URL_PATTERN = /(https?:\/\/|www\.|[a-z0-9-]+\.(com|net|org|io|app|co|me|tv|xyz|info)\b)/i;
const LONG_DIGIT_RUN = new RegExp(`\\d{${MAX_DIGIT_RUN + 1},}`);
const BANNED_PATTERNS = BANNED_WORDS.map((w) => new RegExp(`(^|[^a-z])${w.replace(/\s+/g, '\\s+')}([^a-z]|$)`, 'i'));

export function checkText(value: unknown, field: string, max: number, required: boolean): string[] {
  const reasons: string[] = [];
  if (value === undefined || value === null || value === '') {
    if (required) reasons.push(`${field}:required`);
    return reasons;
  }
  if (typeof value !== 'string') return [`${field}:not_string`];
  if (value.trim().length === 0) return required ? [`${field}:required`] : [];
  if (value.length > max) reasons.push(`${field}:too_long`);
  if (!ASCII_PRINTABLE.test(value)) reasons.push(`${field}:non_ascii`);
  if (URL_PATTERN.test(value)) reasons.push(`${field}:url`);
  if (LONG_DIGIT_RUN.test(value)) reasons.push(`${field}:long_number`);
  if (BANNED_PATTERNS.some((re) => re.test(value))) reasons.push(`${field}:banned_word`);
  return reasons;
}

export interface ValidationResult { ok: boolean; turn: TutorTurn; reasons: string[] }

export function validateTurn(candidate: unknown, opts: { allowlist?: readonly string[] } = {}): ValidationResult {
  const allowlist = new Set(opts.allowlist ?? DEFAULT_ASSET_ALLOWLIST);
  const reasons: string[] = [];
  if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
    return { ok: false, turn: fallbackTurn(), reasons: ['turn:not_object'] };
  }
  const t = candidate as Record<string, unknown>;

  reasons.push(...checkText(t.speech, 'speech', MAX_SPEECH, true));
  reasons.push(...checkText(t.subtitle, 'subtitle', MAX_SUBTITLE, false));
  reasons.push(...checkText(t.nextQuestion, 'nextQuestion', MAX_NEXT_QUESTION, false));

  if (!EMOTIONS.includes(t.emotion as Emotion)) reasons.push('emotion:invalid');
  if (!GESTURES.includes(t.gesture as Gesture)) reasons.push('gesture:invalid');
  if (!LESSON_ACTIONS.includes(t.lessonAction as LessonAction)) reasons.push('lessonAction:invalid');

  const visual = t.visual as Record<string, unknown> | undefined;
  let assetId: string | undefined;
  if (!visual || typeof visual !== 'object' || Array.isArray(visual)) {
    reasons.push('visual:missing');
  } else {
    if (!VISUAL_TYPES.includes(visual.type as VisualType)) reasons.push('visual.type:invalid');
    const rawId = visual.assetId;
    if (rawId !== undefined && rawId !== null && rawId !== '') {
      if (typeof rawId !== 'string' || !allowlist.has(rawId)) reasons.push('visual.assetId:not_allowed');
      else assetId = rawId;
    }
    if (visual.type && visual.type !== 'none' && !assetId && !reasons.includes('visual.assetId:not_allowed')) {
      reasons.push('visual.assetId:required');
    }
  }

  if (reasons.length) return { ok: false, turn: fallbackTurn(), reasons };

  const speech = (t.speech as string).trim();
  const turn: TutorTurn = {
    speech,
    subtitle: (typeof t.subtitle === 'string' && t.subtitle.trim()) || speech,
    emotion: t.emotion as Emotion,
    gesture: t.gesture as Gesture,
    visual: visual!.type === 'none' ? { type: 'none' } : { type: visual!.type as VisualType, assetId },
    lessonAction: t.lessonAction as LessonAction,
  };
  if (typeof t.nextQuestion === 'string' && t.nextQuestion.trim()) turn.nextQuestion = t.nextQuestion.trim();
  return { ok: true, turn, reasons: [] };
}

export function sanitizeTurn(candidate: unknown, opts?: { allowlist?: readonly string[] }): TutorTurn {
  return validateTurn(candidate, opts).turn;
}
