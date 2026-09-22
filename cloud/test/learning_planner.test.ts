import { describe, expect, it } from 'vitest';
import { ApprovedCurriculumRetriever, LearningPlanner, type ParentLearningSettings, type StudentLearningProfile } from '../src/learning';

const settings: ParentLearningSettings = { aiLearningEnabled: true, voiceEnabled: false, dailyLearningTargetMinutes: 10, difficultyPreference: 'balanced' };
const profile: StudentLearningProfile = {
  childProfileId: 'child_123', ageBand: '6-7', gradeLevel: 'grade1', language: 'en',
  skills: [{ skill: 'colors', mastery: 0.9, attempts: 5 }, { skill: 'simple_sentences', mastery: 0.2, attempts: 3 }, { skill: 'family_listening', mastery: 0.6, attempts: 2 }],
  recentLessons: [], preferredActivityTypes: ['prop_play', 'listen_and_choose'], difficultyHistory: ['beginner', 'developing']
};

describe('deterministic learning planner', () => {
  it('chooses the weakest eligible skill without delegating curriculum selection', async () => {
    const plan = await new LearningPlanner(new ApprovedCurriculumRetriever()).plan(profile, settings, ['prop_play', 'listen_and_choose'], 10);
    expect(plan.activities[0].lesson.id).toBe('en-grade1-everyday-sentences-v1');
    expect(plan.activities[0].purpose).toBe('learn');
    expect(plan.rationaleCodes).toContain('weakest_skill_first');
    expect(plan.activities.reduce((sum, item) => sum + item.durationMinutes, 0)).toBeLessThanOrEqual(10);
  });

  it('respects parent disable, language and available-activity constraints', async () => {
    const planner = new LearningPlanner(new ApprovedCurriculumRetriever());
    expect((await planner.plan(profile, { ...settings, aiLearningEnabled: false }, ['prop_play'], 10)).rationaleCodes).toEqual(['ai_disabled']);
    expect((await planner.plan({ ...profile, language: 'ja' }, settings, ['prop_play'], 10)).rationaleCodes).toEqual(['language_not_enabled']);
    expect((await planner.plan(profile, settings, ['minigame'], 10)).rationaleCodes).toEqual(['no_eligible_lesson']);
  });

  it('never exceeds session or daily target duration', async () => {
    const plan = await new LearningPlanner(new ApprovedCurriculumRetriever()).plan(profile, { ...settings, dailyLearningTargetMinutes: 5 }, ['prop_play', 'listen_and_choose'], 30);
    expect(plan.activities.reduce((sum, item) => sum + item.durationMinutes, 0)).toBeLessThanOrEqual(5);
  });
});
