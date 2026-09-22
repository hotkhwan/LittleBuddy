import { CURRICULUM } from './curriculum';
import type { CurriculumLesson, RetrievalQuery, RetrievedLesson } from './types';

const STOP_WORDS = new Set(['a', 'an', 'and', 'for', 'the', 'to', 'who', 'with', 'child', 'lesson', 'english']);
function terms(text: string): string[] {
  return [...new Set(text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').split(/\s+/).filter((term) => term.length > 1 && !STOP_WORDS.has(term)))];
}

export interface CurriculumRetriever { search(query: RetrievalQuery): Promise<RetrievedLesson[]> }

/** Controlled local retriever and deterministic fallback for the managed AI Search adapter. */
export class ApprovedCurriculumRetriever implements CurriculumRetriever {
  constructor(private readonly lessons: readonly CurriculumLesson[] = CURRICULUM) {}

  async search(query: RetrievalQuery): Promise<RetrievedLesson[]> {
    if (query.language !== 'en' || query.subject !== 'english') return [];
    const queryTerms = terms(query.text ?? '');
    return this.lessons
      .filter((lesson) => lesson.language === query.language && lesson.subject === query.subject)
      .filter((lesson) => query.activeOnly === false || lesson.active)
      .filter((lesson) => !query.grade || lesson.grade === query.grade)
      .filter((lesson) => !query.skills?.length || query.skills.includes(lesson.skill))
      .filter((lesson) => !query.lessonTypes?.length || query.lessonTypes.includes(lesson.lessonType))
      .map((lesson) => {
        const searchable = terms([lesson.skill, lesson.learningObjective, ...lesson.targetVocabulary, ...lesson.commonMistakes, lesson.content].join(' '));
        const matchedTerms = queryTerms.filter((term) => searchable.some((word) => word === term || word.startsWith(term) || term.startsWith(word)));
        const score = matchedTerms.length * 10 + (query.grade === lesson.grade ? 5 : 0) + (query.skills?.includes(lesson.skill) ? 8 : 0) + (lesson.active ? 1 : 0);
        return { lesson, score, matchedTerms };
      })
      .filter((result) => queryTerms.length === 0 || result.matchedTerms.length > 0)
      .sort((a, b) => b.score - a.score || a.lesson.id.localeCompare(b.lesson.id))
      .slice(0, Math.min(Math.max(query.limit ?? 5, 1), 20));
  }
}

export interface ManagedSearchClient { search(input: { query: string; filter: Record<string, string | boolean>; limit: number }): Promise<Array<{ id: string; score: number }>> }

/** Maps managed-search ids back to the approved catalog; unknown/draft documents never cross the boundary. */
export class ManagedCurriculumRetriever implements CurriculumRetriever {
  constructor(private readonly client: ManagedSearchClient, private readonly fallback = new ApprovedCurriculumRetriever()) {}
  async search(query: RetrievalQuery): Promise<RetrievedLesson[]> {
    if (query.language !== 'en' || query.subject !== 'english') return [];
    try {
      const local = await this.fallback.search({ ...query, text: undefined, limit: 20 });
      const approved = new Map(local.map((r) => [r.lesson.id, r.lesson]));
      const rows = await this.client.search({ query: query.text ?? '', filter: { language: query.language, subject: query.subject, ...(query.grade ? { grade: query.grade } : {}), active: true }, limit: Math.min(query.limit ?? 5, 20) });
      return rows.flatMap((row) => {
        const lesson = approved.get(row.id);
        return lesson ? [{ lesson, score: Number.isFinite(row.score) ? row.score : 0, matchedTerms: [] }] : [];
      });
    } catch {
      return this.fallback.search(query);
    }
  }
}
