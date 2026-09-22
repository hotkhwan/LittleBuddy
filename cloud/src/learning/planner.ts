import type { ActivityType, CurriculumLesson, LearningPlan, ParentLearningSettings, PlannedActivity, StudentLearningProfile } from './types';
import type { CurriculumRetriever } from './retrieval';

function mastery(profile: StudentLearningProfile, skill: string): number { return profile.skills.find((item) => item.skill === skill)?.mastery ?? 0; }
function preferenceScore(profile: StudentLearningProfile, activity: ActivityType): number { const i = profile.preferredActivityTypes.indexOf(activity); return i < 0 ? 0 : profile.preferredActivityTypes.length - i; }

export class LearningPlanner {
  constructor(private readonly retriever: CurriculumRetriever) {}

  async plan(profile: StudentLearningProfile, settings: ParentLearningSettings, availableActivities: readonly ActivityType[], sessionMinutes: number): Promise<LearningPlan> {
    if (!settings.aiLearningEnabled) return { objective: 'Continue an offline Little Days lesson.', activities: [], rationaleCodes: ['ai_disabled'] };
    if (profile.language !== 'en') return { objective: 'Continue an offline Little Days lesson.', activities: [], rationaleCodes: ['language_not_enabled'] };
    const budget = Math.max(1, Math.min(sessionMinutes, settings.dailyLearningTargetMinutes, 60));
    const weakest = [...profile.skills].sort((a, b) => a.mastery - b.mastery || b.attempts - a.attempts)[0];
    const retrieved = await this.retriever.search({ language: 'en', subject: 'english', grade: profile.gradeLevel, skills: weakest ? [weakest.skill] : undefined, activeOnly: true, limit: 12 });
    const ranked = retrieved
      .filter(({ lesson }) => availableActivities.includes(lesson.activityRecommendation) && lesson.durationMinutes <= budget)
      .sort((a, b) => {
        const score = (lesson: CurriculumLesson) => (1 - mastery(profile, lesson.skill)) * 100 + preferenceScore(profile, lesson.activityRecommendation) * 5 - (profile.recentLessons.includes(lesson.id) ? 25 : 0);
        return score(b.lesson) - score(a.lesson) || b.score - a.score || a.lesson.id.localeCompare(b.lesson.id);
      });
    if (!ranked.length) return { objective: 'Continue an offline Little Days lesson.', activities: [], rationaleCodes: ['no_eligible_lesson'] };
    const primary = ranked[0].lesson;
    const activities: PlannedActivity[] = [{ lesson: primary, activityType: primary.activityRecommendation, durationMinutes: primary.durationMinutes, purpose: mastery(profile, primary.skill) >= 0.8 ? 'review' : 'learn' }];
    const remaining = budget - primary.durationMinutes;
    const followUp = ranked.find(({ lesson }) => lesson.id !== primary.id && lesson.durationMinutes <= remaining);
    if (followUp) activities.push({ lesson: followUp.lesson, activityType: followUp.lesson.activityRecommendation, durationMinutes: followUp.lesson.durationMinutes, purpose: 'practice' });
    return { objective: primary.learningObjective, activities, rationaleCodes: [weakest ? 'weakest_skill_first' : 'grade_foundation', profile.recentLessons.includes(primary.id) ? 'recent_review' : 'spaced_selection', settings.difficultyPreference] };
  }
}
