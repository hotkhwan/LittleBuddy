// The shared TutorTurn truth table: the same file the client (tutor_turn.gd)
// and the prototype (backend/test/validator.test.js) run.
import { describe, expect, it } from 'vitest';
import fixtures from '../../game/content/tutor/turn_fixtures.json';
import { DEFAULT_ASSET_ALLOWLIST, checkText, fallbackTurn, validateTurn } from '../src/tutor/turn_validator';
import { ASSET_ALLOWLIST } from '../src/tutor/content';
import { LESSONS, resolveLessonContext } from '../src/tutor/lessons';

interface Case { name: string; input: unknown; expect: 'valid' | 'fallback'; normalized?: Record<string, unknown>; reasonPrefix?: string }
const cases = (fixtures as { cases: Case[] }).cases;

describe('shared fixtures (game/content/tutor/turn_fixtures.json)', () => {
  it('has at least 12 cases', () => {
    expect(cases.length).toBeGreaterThanOrEqual(12);
  });
  it.each(cases.map((c) => [c.name, c] as const))('%s', (_name, c) => {
    const r = validateTurn(c.input, { allowlist: DEFAULT_ASSET_ALLOWLIST });
    if (c.expect === 'valid') {
      expect(r.ok, `reasons ${r.reasons.join(',')}`).toBe(true);
      for (const [k, v] of Object.entries(c.normalized ?? {})) expect((r.turn as unknown as Record<string, unknown>)[k]).toEqual(v);
    } else {
      expect(r.ok).toBe(false);
      expect(r.turn).toEqual(fallbackTurn());
      if (c.reasonPrefix) expect(r.reasons.some((x) => x.startsWith(c.reasonPrefix!)), r.reasons.join(',')).toBe(true);
    }
  });
});

describe('validator rules', () => {
  it('fallback turn matches the contract and the fixture file', () => {
    expect(fallbackTurn()).toEqual({ speech: "Let's try together!", subtitle: "Let's try together!", emotion: 'encouraging', gesture: 'tilt', visual: { type: 'none' }, lessonAction: 'retry' });
    expect(validateTurn(fallbackTurn()).ok).toBe(true);
    const f = (fixtures as { fallback: Record<string, unknown> }).fallback;
    expect(f.speech).toBe(fallbackTurn().speech);
  });

  it('every enum value is accepted and one-off values are not', () => {
    const base = { speech: 'Hi!', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'retry' };
    for (const emotion of ['neutral', 'listening', 'thinking', 'happy', 'encouraging', 'smile']) expect(validateTurn({ ...base, emotion }).ok, emotion).toBe(true);
    for (const gesture of ['none', 'nod', 'tilt', 'point', 'clap', 'wave', 'thumbsUp', 'celebrate', 'listening', 'thinking', 'encourage']) expect(validateTurn({ ...base, gesture }).ok, gesture).toBe(true);
    for (const lessonAction of ['next_question', 'retry', 'give_hint', 'complete', 'end_session', 'switch_lesson', 'jump_step']) expect(validateTurn({ ...base, lessonAction }).ok, lessonAction).toBe(true);
    for (const id of DEFAULT_ASSET_ALLOWLIST) expect(validateTurn({ ...base, visual: { type: 'flashcard', assetId: id } }).ok, id).toBe(true);
    expect(validateTurn({ ...base, emotion: 'Happy' }).ok).toBe(false);
    expect(validateTurn({ ...base, gesture: 'NOD' }).ok).toBe(false);
    expect(validateTurn({ ...base, lessonAction: 'next' }).ok).toBe(false);
    expect(validateTurn({ ...base, visual: { type: 'gif', assetId: 'cat' } }).ok).toBe(false);
    expect(validateTurn({ ...base, visual: { type: 'none', assetId: 'not_allowed' } }).ok).toBe(false);
  });

  it('checkText edge cases', () => {
    expect(checkText('a'.repeat(160), 'speech', 160, true)).toEqual([]);
    expect(checkText('a'.repeat(161), 'speech', 160, true)).toEqual(['speech:too_long']);
    expect(checkText('12345678901234567890', 'speech', 160, true)).toEqual([]);
    expect(checkText('www.example.org', 'speech', 160, true)).toEqual(['speech:url']);
    expect(checkText('Hello. Nice, right? Yes: "good"!', 'speech', 160, true)).toEqual([]);
    expect(checkText('shut   up', 'speech', 160, true)).toEqual(['speech:banned_word']);
  });

  it('bundled allowlist is the shared file and lessons resolve server side', () => {
    expect(ASSET_ALLOWLIST.source).toBe('file');
    expect(ASSET_ALLOWLIST.ids).toContain('color_red');
    expect([...LESSONS.keys()].sort()).toEqual(['animals_cat_dog', 'colors_red_blue', 'english_colors_fruits', 'everyday_cup_spoon', 'numbers_one_two_three', 'welcome_choose']);
    const ctx = resolveLessonContext(LESSONS.get('colors_red_blue')!, { stepId: 's02_red', outcome: 'correct', matched: 'RED' });
    expect(ctx?.matched).toBe('red');
    expect(ctx?.lessonAction).toBe('next_question');
    expect(ctx?.nextQuestionText).toBe('What colour is this?');
    expect(resolveLessonContext(LESSONS.get('colors_red_blue')!, { stepId: 'nope', outcome: 'correct' })).toBeNull();
    const last = resolveLessonContext(LESSONS.get('colors_red_blue')!, { stepId: 's03_blue', outcome: 'correct' });
    expect(last?.lessonAction).toBe('complete');
  });
});
