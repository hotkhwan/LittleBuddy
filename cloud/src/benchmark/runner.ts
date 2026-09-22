import { BENCHMARK_CASES, type BenchmarkCase } from './cases';
import type { AIMessage, WorkersAIResult } from '../tutor/workers_ai_provider';

export interface BenchmarkAdapter {
  readonly name: string;
  chat(input: { messages: AIMessage[]; maxTokens: number; temperature: number }): Promise<WorkersAIResult>;
  structured(input: { messages: AIMessage[]; schema: Record<string, unknown>; maxTokens: number; temperature: number }): Promise<WorkersAIResult>;
  toolCall(input: { messages: AIMessage[]; tools: NonNullable<BenchmarkCase['tools']>; maxTokens: number; temperature: number }): Promise<WorkersAIResult>;
}

export interface BenchmarkSample {
  caseId: string;
  model: string;
  repetition: number;
  startedAt: string;
  latencyMs: number;
  ok: boolean;
  text: string;
  parsed?: unknown;
  toolCalls: WorkersAIResult['toolCalls'];
  usage: WorkersAIResult['usage'];
  error?: { name: string; message: string };
  raw?: unknown;
}

export interface BenchmarkSummary {
  model: string;
  samples: number;
  successes: number;
  errors: number;
  medianLatencyMs: number;
  p95LatencyMs: number;
  totalInputTokens: number;
  totalOutputTokens: number;
  toolExactMatches: number;
  structuredValid: number;
}

export interface BenchmarkRun {
  schemaVersion: 1;
  generatedAt: string;
  temperature: number;
  maxTokens: number;
  repetitions: number;
  samples: BenchmarkSample[];
  summary: BenchmarkSummary;
}

export async function runBenchmark(
  adapter: BenchmarkAdapter,
  options: { cases?: readonly BenchmarkCase[]; repetitions?: number; temperature?: number; maxTokens?: number; includeRaw?: boolean } = {},
): Promise<BenchmarkRun> {
  const cases = options.cases ?? BENCHMARK_CASES;
  const repetitions = Math.max(1, Math.trunc(options.repetitions ?? 3));
  const temperature = options.temperature ?? 0.2;
  const maxTokens = options.maxTokens ?? 160;
  const samples: BenchmarkSample[] = [];

  for (const testCase of cases) {
    for (let repetition = 1; repetition <= repetitions; repetition += 1) {
      const startedAt = new Date().toISOString();
      const started = performance.now();
      try {
        const messages: AIMessage[] = [{ role: 'system', content: testCase.system }, { role: 'user', content: testCase.prompt }];
        const result = testCase.tools
          ? await adapter.toolCall({ messages, tools: testCase.tools, maxTokens, temperature })
          : testCase.structuredSchema
            ? await adapter.structured({ messages, schema: testCase.structuredSchema, maxTokens, temperature })
            : await adapter.chat({ messages, maxTokens, temperature });
        samples.push({
          caseId: testCase.id, model: adapter.name, repetition, startedAt,
          latencyMs: elapsed(started), ok: true, text: result.text, parsed: result.parsed,
          toolCalls: result.toolCalls, usage: result.usage,
          ...(options.includeRaw ? { raw: result.raw } : {}),
        });
      } catch (error) {
        samples.push({
          caseId: testCase.id, model: adapter.name, repetition, startedAt,
          latencyMs: elapsed(started), ok: false, text: '', toolCalls: [],
          usage: { llmInputTokens: 0, llmOutputTokens: 0 },
          error: { name: error instanceof Error ? error.name : 'Error', message: error instanceof Error ? error.message : String(error) },
        });
      }
    }
  }

  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    temperature,
    maxTokens,
    repetitions,
    samples,
    summary: summarize(adapter.name, samples),
  };
}

export function summarize(model: string, samples: readonly BenchmarkSample[]): BenchmarkSummary {
  const successful = samples.filter((sample) => sample.ok);
  const latencies = successful.map((sample) => sample.latencyMs).sort((a, b) => a - b);
  return {
    model,
    samples: samples.length,
    successes: successful.length,
    errors: samples.length - successful.length,
    medianLatencyMs: percentile(latencies, 0.5),
    p95LatencyMs: percentile(latencies, 0.95),
    totalInputTokens: successful.reduce((sum, sample) => sum + sample.usage.llmInputTokens, 0),
    totalOutputTokens: successful.reduce((sum, sample) => sum + sample.usage.llmOutputTokens, 0),
    toolExactMatches: successful.filter((sample) => sample.caseId === 'TOOL-1' && sample.toolCalls.length === 1 && sample.toolCalls[0]?.name === 'show_learning_card' && sample.toolCalls[0]?.arguments.assetId === 'milk').length,
    structuredValid: successful.filter((sample) => sample.caseId === 'JSON-1' && isRecord(sample.parsed) && sample.parsed.expectedAnswer === 'apple').length,
  };
}

function percentile(sorted: readonly number[], quantile: number): number {
  if (!sorted.length) return 0;
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * quantile) - 1)] ?? 0;
}

function elapsed(started: number): number {
  return Math.max(0, Math.round((performance.now() - started) * 100) / 100);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

