export const ENABLED_LANGUAGES = ['en'] as const;
export const ROADMAP_LANGUAGES = ['zh', 'ja', 'ko'] as const;
export const ENABLED_SUBJECTS = ['english'] as const;
export const ROADMAP_SUBJECTS = ['mental_math', 'mathematics', 'science', 'general_knowledge', 'dance', 'vocal', 'music', 'creative_play'] as const;

export type Language = typeof ENABLED_LANGUAGES[number] | typeof ROADMAP_LANGUAGES[number];
export type Subject = typeof ENABLED_SUBJECTS[number] | typeof ROADMAP_SUBJECTS[number];
export type Grade = 'prek' | 'kindergarten' | 'grade1' | 'grade2' | 'grade3' | 'grade4';
export type Difficulty = 'beginner' | 'developing' | 'secure' | 'stretch';
export type LessonType = 'vocabulary' | 'phonics' | 'listening' | 'speaking' | 'reading' | 'comprehension' | 'sentence_building';
export type ActivityType = 'learning_cards' | 'prop_play' | 'listen_and_choose' | 'say_and_show' | 'minigame' | 'shared_reading';

export interface DifficultyVariant { level: Difficulty; adaptation: string }
export interface ExpectedResponse { promptId: string; accepted: string[] }

export interface CurriculumLesson {
  id: string;
  version: number;
  publishedAt: string;
  active: boolean;
  language: Language;
  subject: Subject;
  ageBand: string;
  grade: Grade;
  skill: string;
  difficulty: Difficulty;
  lessonType: LessonType;
  learningStandard: string;
  learningObjective: string;
  prerequisites: string[];
  targetVocabulary: string[];
  teacherPrompts: string[];
  expectedResponses: ExpectedResponse[];
  hints: string[];
  successCriteria: string[];
  commonMistakes: string[];
  activityRecommendation: ActivityType;
  learningProps: string[];
  difficultyVariants: DifficultyVariant[];
  durationMinutes: number;
  content: string;
}

export interface SkillProgress { skill: string; mastery: number; attempts: number; lastPracticedAt?: string }
export interface StudentLearningProfile {
  childProfileId: string;
  ageBand: string;
  gradeLevel: Grade;
  language: Language;
  skills: SkillProgress[];
  recentLessons: string[];
  preferredActivityTypes: ActivityType[];
  difficultyHistory: Difficulty[];
}

export interface ParentLearningSettings {
  aiLearningEnabled: boolean;
  voiceEnabled: boolean;
  dailyLearningTargetMinutes: number;
  difficultyPreference: 'supportive' | 'balanced' | 'challenging';
}

export interface RetrievalQuery {
  text?: string;
  language: Language;
  subject: Subject;
  grade?: Grade;
  skills?: string[];
  lessonTypes?: LessonType[];
  activeOnly?: boolean;
  limit?: number;
}

export interface RetrievedLesson { lesson: CurriculumLesson; score: number; matchedTerms: string[] }
export interface PlannedActivity { lesson: CurriculumLesson; activityType: ActivityType; durationMinutes: number; purpose: 'learn' | 'practice' | 'review' }
export interface LearningPlan { objective: string; activities: PlannedActivity[]; rationaleCodes: string[] }
