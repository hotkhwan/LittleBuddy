import type { ManagedSearchClient } from './retrieval';

interface SearchBinding {
  get(name: string): {
    search(input: Record<string, unknown>): Promise<{ chunks?: unknown[] }>;
  };
}

/** Thin adapter around the managed namespace binding. It returns only catalog IDs and scores. */
export class CloudflareCurriculumSearch implements ManagedSearchClient {
  constructor(private readonly binding: SearchBinding, private readonly instanceName = 'little-days-curriculum') {}

  async search(input: { query: string; filter: Record<string, string | boolean>; limit: number }): Promise<Array<{ id: string; score: number }>> {
    const response = await this.binding.get(this.instanceName).search({
      messages: [{ role: 'user', content: input.query }],
      ai_search_options: {
        retrieval: {
          max_num_results: Math.min(Math.max(input.limit, 1), 20),
          filters: input.filter,
        },
      },
    });
    return (response.chunks ?? []).flatMap((value) => {
      if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
      const chunk = value as Record<string, unknown>;
      const metadata = chunk.metadata && typeof chunk.metadata === 'object' && !Array.isArray(chunk.metadata) ? chunk.metadata as Record<string, unknown> : {};
      const item = chunk.item && typeof chunk.item === 'object' && !Array.isArray(chunk.item) ? chunk.item as Record<string, unknown> : {};
      const source = [metadata.filename, metadata.key, item.key, chunk.filename, chunk.id].find((candidate) => typeof candidate === 'string') as string | undefined;
      const match = source?.match(/([a-z0-9][a-z0-9_-]+)\.md$/i);
      if (!match) return [];
      const score = Number(chunk.score ?? chunk.similarity ?? 0);
      return [{ id: match[1], score: Number.isFinite(score) ? score : 0 }];
    });
  }
}
