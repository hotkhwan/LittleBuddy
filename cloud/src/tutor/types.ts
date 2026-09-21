// Shared tutor types. TutorTurn mirrors docs/ALIZ_TUTOR_CONTRACTS.md exactly.
export type Emotion = 'neutral' | 'listening' | 'thinking' | 'happy' | 'encouraging' | 'smile';
export type Gesture = 'none' | 'nod' | 'tilt' | 'point' | 'clap' | 'wave' | 'thumbsUp' | 'celebrate' | 'listening' | 'thinking' | 'encourage';
export type VisualType = 'none' | 'flashcard' | 'model';
export type LessonAction = 'next_question' | 'retry' | 'give_hint' | 'complete' | 'end_session' | 'switch_lesson' | 'jump_step';
export type Outcome = 'correct' | 'incorrect' | 'unclear';

export interface TutorTurn {
  speech: string;
  subtitle: string;
  emotion: Emotion;
  gesture: Gesture;
  visual: { type: VisualType; assetId?: string };
  lessonAction: LessonAction;
  nextQuestion?: string;
}

export interface LessonContext {
  stepId: string;
  outcome: Outcome;
  expectedAnswers: string[];
  hint: string;
  nextQuestionText: string;
  visualAssetId: string;
  matched: string;
  lessonAction: string;
  successLine?: string;
  answerLine?: string;
  encouragement?: string;
  isLastStep?: boolean;
}

export interface QuotaState {
  entitlement: 'free' | 'family_club';
  dailyAllowanceSeconds: number;
  usedSeconds: number;
  remainingSeconds: number;
  resetAtUtc: string;
  dailyTurnAllowance: number;
  usedTurns: number;
}
