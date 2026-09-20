// TutorTurn validator: the server half of the shared contract in
// docs/ALIZ_TUTOR_CONTRACTS.md. Same rules as the client validator
// (game/scripts/tutor/turn/tutor_turn.gd); both run the same fixture file.
//
// Anything invalid -> the safe fallback turn. The validator never throws on
// bad input and never lets a provider-authored string through unchecked.
import fs from 'node:fs';

export const EMOTIONS = Object.freeze(['neutral', 'listening', 'thinking', 'happy', 'encouraging', 'smile']);
export const GESTURES = Object.freeze(['none', 'nod', 'tilt', 'point', 'clap', 'wave']);
export const VISUAL_TYPES = Object.freeze(['none', 'flashcard', 'model']);
export const LESSON_ACTIONS = Object.freeze(['next_question', 'retry', 'give_hint', 'complete', 'end_session']);

export const MAX_SPEECH = 160;
export const MAX_SUBTITLE = 160;
export const MAX_NEXT_QUESTION = 120;
export const MAX_DIGIT_RUN = 20;

// Mirror of the contract's approved list, used when the shared file
// game/content/tutor/assets_allowlist.json is not present (e.g. before Agent B lands it).
export const DEFAULT_ASSET_ALLOWLIST = Object.freeze([
  'apple_red', 'banana_yellow', 'cat', 'dog', 'number_1', 'number_2', 'number_3',
  'color_blue', 'color_green', 'color_red', 'color_yellow', 'orange_orange', 'grapes_purple',
]);

// Small, deliberately conservative list. Matched on word boundaries, case-insensitive.
// Ages 3-6: no violence, no scary/adult themes, no personal-data prompts.
export const BANNED_WORDS = Object.freeze([
  'kill', 'die', 'dead', 'death', 'murder', 'blood', 'gun', 'knife', 'shoot', 'stab', 'bomb',
  'hate', 'stupid', 'idiot', 'dumb', 'ugly', 'loser', 'shut up',
  'damn', 'hell', 'crap', 'sex', 'sexy', 'naked', 'drug', 'drugs', 'beer', 'wine', 'drunk',
  'password', 'credit card', 'phone number', 'home address', 'where do you live', 'last name',
]);

export const FALLBACK_TURN = Object.freeze({
  speech: "Let's try together!",
  emotion: 'encouraging',
  gesture: 'tilt',
  visual: Object.freeze({ type: 'none' }),
  lessonAction: 'retry',
});

/** @returns {import('./types.js').TutorTurn} */
export function fallbackTurn() {
  return { speech: FALLBACK_TURN.speech, subtitle: FALLBACK_TURN.speech, emotion: 'encouraging', gesture: 'tilt', visual: { type: 'none' }, lessonAction: 'retry' };
}

/**
 * Load the asset allowlist from the shared JSON file. Accepts either a bare
 * array of ids or {"assets":[{"id":...}|"id", ...]} / {"allowlist":[...]}.
 * Falls back to the contract's list when the file is missing or unreadable.
 * @param {string} filePath
 * @returns {{ids: string[], source: 'file'|'default'}}
 */
export function loadAssetAllowlist(filePath) {
  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const list = Array.isArray(raw) ? raw : (raw.assets ?? raw.allowlist ?? raw.ids ?? raw.assetIds);
    if (Array.isArray(list)) {
      const ids = list
        .map((entry) => (typeof entry === 'string' ? entry : entry && (entry.id ?? entry.assetId)))
        .filter((id) => typeof id === 'string' && id.length > 0);
      if (ids.length) return { ids, source: 'file' };
    }
  } catch {
    /* fall through */
  }
  return { ids: [...DEFAULT_ASSET_ALLOWLIST], source: 'default' };
}

const ASCII_PRINTABLE = /^[\x20-\x7E]*$/;
const URL_PATTERN = /(https?:\/\/|www\.|[a-z0-9-]+\.(com|net|org|io|app|co|me|tv|xyz|info)\b)/i;
const LONG_DIGIT_RUN = new RegExp(`\\d{${MAX_DIGIT_RUN + 1},}`);
const BANNED_PATTERNS = BANNED_WORDS.map((w) => new RegExp(`(^|[^a-z])${w.replace(/\s+/g, '\\s+')}([^a-z]|$)`, 'i'));

/**
 * Check one text field. Returns a list of reasons (empty = OK).
 * @param {unknown} value
 * @param {string} field
 * @param {number} max
 * @param {boolean} required
 */
export function checkText(value, field, max, required) {
  const reasons = [];
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

/**
 * Validate and normalise a candidate TutorTurn.
 * @param {unknown} candidate
 * @param {{allowlist?: readonly string[]}} [opts]
 * @returns {{ok: boolean, turn: import('./types.js').TutorTurn, reasons: string[]}}
 */
export function validateTurn(candidate, opts = {}) {
  const allowlist = new Set(opts.allowlist ?? DEFAULT_ASSET_ALLOWLIST);
  /** @type {string[]} */
  const reasons = [];
  if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
    return { ok: false, turn: fallbackTurn(), reasons: ['turn:not_object'] };
  }
  const t = /** @type {Record<string, any>} */ (candidate);

  reasons.push(...checkText(t.speech, 'speech', MAX_SPEECH, true));
  reasons.push(...checkText(t.subtitle, 'subtitle', MAX_SUBTITLE, false));
  reasons.push(...checkText(t.nextQuestion, 'nextQuestion', MAX_NEXT_QUESTION, false));

  if (!EMOTIONS.includes(t.emotion)) reasons.push('emotion:invalid');
  if (!GESTURES.includes(t.gesture)) reasons.push('gesture:invalid');
  if (!LESSON_ACTIONS.includes(t.lessonAction)) reasons.push('lessonAction:invalid');

  const visual = t.visual;
  let assetId;
  if (!visual || typeof visual !== 'object' || Array.isArray(visual)) {
    reasons.push('visual:missing');
  } else {
    if (!VISUAL_TYPES.includes(visual.type)) reasons.push('visual.type:invalid');
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

  /** @type {import('./types.js').TutorTurn} */
  const turn = {
    speech: t.speech.trim(),
    subtitle: (typeof t.subtitle === 'string' && t.subtitle.trim()) || t.speech.trim(),
    emotion: t.emotion,
    gesture: t.gesture,
    visual: visual.type === 'none' ? { type: 'none' } : { type: visual.type, assetId },
    lessonAction: t.lessonAction,
  };
  if (typeof t.nextQuestion === 'string' && t.nextQuestion.trim()) turn.nextQuestion = t.nextQuestion.trim();
  return { ok: true, turn, reasons: [] };
}

/**
 * Convenience: always returns a safe TutorTurn.
 * @param {unknown} candidate
 * @param {{allowlist?: readonly string[]}} [opts]
 */
export function sanitizeTurn(candidate, opts) {
  return validateTurn(candidate, opts).turn;
}
