import { describe, expect, it } from 'vitest';
import { buildLearningReport } from '../src/learning/report';

describe('learning report', () => {
  it('uses only deterministic skill progress and recommends the lowest mastery', () => {
    expect(buildLearningReport('2026-09-22', [
      { skill: 'colors', mastery: 0.9, attempts: 4 },
      { skill: 'animals', mastery: 0.3, attempts: 2 },
      { skill: 'unused', mastery: 0, attempts: 0 },
    ])).toEqual({
      date: '2026-09-22',
      practicedSkills: [
        { skill: 'colors', mastery: 0.9, attempts: 4 },
        { skill: 'animals', mastery: 0.3, attempts: 2 },
      ],
      suggestedNextSkill: 'animals',
    });
  });
});
