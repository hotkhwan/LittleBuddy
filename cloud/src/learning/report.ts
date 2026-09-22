import type { SkillProgress } from './types';

export interface LearningReport {
  date: string;
  practicedSkills: Array<{ skill: string; attempts: number; mastery: number }>;
  suggestedNextSkill: string | null;
}

/** Deterministic parent summary from progress counters; never infers traits, diagnoses, or emotions. */
export function buildLearningReport(date: string, skills: readonly SkillProgress[]): LearningReport {
  const practicedSkills = skills
    .filter((skill) => skill.attempts > 0)
    .map(({ skill, attempts, mastery }) => ({ skill, attempts: Math.max(0, Math.trunc(attempts)), mastery: Math.min(1, Math.max(0, mastery)) }))
    .sort((a, b) => b.attempts - a.attempts || a.skill.localeCompare(b.skill));
  const next = [...practicedSkills].sort((a, b) => a.mastery - b.mastery || b.attempts - a.attempts)[0];
  return { date, practicedSkills, suggestedNextSkill: next?.skill ?? null };
}
