import { describe, expect, it } from 'vitest';
import { BENCHMARK_CASES } from '../src/benchmark/cases';
import { runBenchmark, summarize, type BenchmarkAdapter, type BenchmarkSample } from '../src/benchmark/runner';

describe('benchmark cases', () => {
  it('covers the fixed and expanded learning/safety scenarios', () => {
    expect(BENCHMARK_CASES.length).toBeGreaterThanOrEqual(20);
    expect(BENCHMARK_CASES.map((c) => c.id)).toEqual(expect.arrayContaining([
      'THAI-1', 'EN-1', 'G1-1', 'G2-1', 'G3-1', 'G4-1', 'SAFE-1', 'SAFE-2', 'SHORT-1', 'TOOL-1',
      'PREK-1', 'K-1', 'G3-READ-1', 'G4-CONV-1', 'MIXED-1', 'SAFE-PERSONAL-2', 'UNKNOWN-1', 'JSON-1',
    ]));
  });
});

describe('benchmark runner', () => {
  it('runs chat, tools, and structured cases and preserves serializable evidence', async () => {
    const base = { usage: { llmInputTokens: 10, llmOutputTokens: 2 }, raw: { requestId: 'test' } };
    const adapter: BenchmarkAdapter = {
      name: 'workers-ai:test',
      async chat() { return { ...base, text: 'Answer', toolCalls: [] }; },
      async toolCall() { return { ...base, text: 'This is milk.', toolCalls: [{ name: 'show_learning_card', arguments: { assetId: 'milk' } }] }; },
      async structured() { return { ...base, text: '{"expectedAnswer":"apple"}', parsed: { prompt: 'What is this?', expectedAnswer: 'apple' }, toolCalls: [] }; },
    };
    const selected = BENCHMARK_CASES.filter((c) => ['EN-1', 'TOOL-1', 'JSON-1'].includes(c.id));
    const run = await runBenchmark(adapter, { cases: selected, repetitions: 2, includeRaw: true });
    expect(run.samples).toHaveLength(6);
    expect(run.summary).toMatchObject({ samples: 6, successes: 6, errors: 0, totalInputTokens: 60, totalOutputTokens: 12, toolExactMatches: 2, structuredValid: 2 });
    expect(() => JSON.stringify(run)).not.toThrow();
  });

  it('records errors without aborting remaining samples', async () => {
    let call = 0;
    const adapter: BenchmarkAdapter = {
      name: 'test',
      async chat() { call += 1; if (call === 1) throw new Error('temporary'); return { text: 'ok', toolCalls: [], usage: { llmInputTokens: 1, llmOutputTokens: 1 }, raw: null }; },
      async toolCall() { throw new Error('unused'); },
      async structured() { throw new Error('unused'); },
    };
    const run = await runBenchmark(adapter, { cases: [BENCHMARK_CASES.find((c) => c.id === 'EN-1')!], repetitions: 2 });
    expect(run.summary).toMatchObject({ samples: 2, successes: 1, errors: 1 });
    expect(run.samples[0]?.error?.message).toBe('temporary');
    expect(run.samples[1]?.ok).toBe(true);
  });

  it('calculates nearest-rank median and p95 latency', () => {
    const samples = [10, 20, 30, 40, 100].map((latencyMs): BenchmarkSample => ({ caseId: 'EN-1', model: 'm', repetition: 1, startedAt: '', latencyMs, ok: true, text: '', toolCalls: [], usage: { llmInputTokens: 1, llmOutputTokens: 2 } }));
    expect(summarize('m', samples)).toMatchObject({ medianLatencyMs: 30, p95LatencyMs: 100, totalInputTokens: 5, totalOutputTokens: 10 });
  });
});
