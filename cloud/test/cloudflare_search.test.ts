import { describe, expect, it, vi } from 'vitest';
import { CloudflareCurriculumSearch } from '../src/learning/cloudflare_search';

describe('CloudflareCurriculumSearch', () => {
  it('maps only indexed curriculum filenames to lesson IDs', async () => {
    const search = vi.fn().mockResolvedValue({ chunks: [
      { score: 0.9, item: { key: 'curriculum/english/grade1/en-grade1-family-listening-v1.md' } },
      { score: 0.7, item: { key: 'curriculum/english/grade1/en-grade1-family-listening-v1.md' } },
      { score: 1, item: { key: 'untrusted-without-markdown-extension' } },
    ] });
    const client = new CloudflareCurriculumSearch({ get: vi.fn(() => ({ search })) });
    await expect(client.search({ query: 'family words', filter: { language: 'en', active: true }, limit: 5 })).resolves.toEqual([
      { id: 'en-grade1-family-listening-v1', score: 0.9 },
    ]);
    expect(search).toHaveBeenCalledWith(expect.objectContaining({ ai_search_options: { retrieval: { max_num_results: 5, filters: { language: 'en', active: true } } } }));
  });
});
