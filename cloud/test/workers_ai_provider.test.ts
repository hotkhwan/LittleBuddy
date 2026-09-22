import { describe, expect, it, vi } from 'vitest';
import { createWorkersAIRoutedTurnProvider, createWorkersAITurnProvider, WorkersAIProvider, WorkersAIProviderError, type WorkersAIBinding } from '../src/tutor/workers_ai_provider';

function binding(run: WorkersAIBinding['run']): WorkersAIBinding { return { run }; }

describe('WorkersAIProvider', () => {
  it('normalizes text and token usage', async () => {
    const run = vi.fn(async () => ({ response: 'Hello!', usage: { prompt_tokens: 12, completion_tokens: 4, total_tokens: 16 } }));
    const provider = new WorkersAIProvider({ ai: binding(run), model: '@cf/example/model' });
    const result = await provider.chat({ messages: [{ role: 'user', content: 'Hi' }] });
    expect(result.text).toBe('Hello!');
    expect(result.usage).toEqual({ llmInputTokens: 12, llmOutputTokens: 4, totalTokens: 16 });
    expect(run).toHaveBeenCalledWith('@cf/example/model', expect.objectContaining({ max_tokens: 1024, temperature: 0.2 }), {});
  });

  it('uses AI Gateway with personalized caching disabled by default', async () => {
    const run = vi.fn(async () => ({ response: 'Safe response' }));
    const provider = new WorkersAIProvider({ ai: binding(run), model: 'model', gateway: { id: 'little-days-ai' } });
    await provider.chat({ messages: [{ role: 'user', content: 'Hello' }] });
    expect(run).toHaveBeenCalledWith('model', expect.anything(), { gateway: { id: 'little-days-ai', skipCache: true } });
  });

  it('parses fenced structured JSON', async () => {
    const run = vi.fn(async () => ({ response: '```json\n{"answer":"green"}\n```', usage: { input_tokens: 8, output_tokens: 3 } }));
    const provider = new WorkersAIProvider({ ai: binding(run), model: 'model' });
    const result = await provider.structured({ messages: [{ role: 'user', content: 'Color?' }], schema: { name: 'answer', schema: { type: 'object' } } });
    expect(result.parsed).toEqual({ answer: 'green' });
    expect(run).toHaveBeenCalledWith('model', expect.objectContaining({ response_format: { type: 'json_schema', json_schema: { type: 'object' } } }), {});
  });

  it('accepts object-valued structured responses from the binding', async () => {
    const provider = new WorkersAIProvider({ ai: binding(async () => ({ response: { answer: 'green' }, usage: { prompt_tokens: 2, completion_tokens: 1 } })), model: 'model' });
    const result = await provider.structured({ messages: [{ role: 'user', content: 'Color?' }], schema: { type: 'object' } });
    expect(result.parsed).toEqual({ answer: 'green' });
  });

  it('normalizes OpenAI-style function calls', async () => {
    const run = vi.fn(async () => ({ tool_calls: [{ id: 'call-1', function: { name: 'show_learning_card', arguments: '{"assetId":"milk"}' } }] }));
    const provider = new WorkersAIProvider({ ai: binding(run), model: 'model' });
    const tool = { name: 'show_learning_card', description: 'Show card', parameters: { type: 'object' } };
    const result = await provider.toolCall({
      messages: [{ role: 'user', content: 'Show milk' }],
      tools: [tool],
    });
    expect(result.toolCalls).toEqual([{ id: 'call-1', name: 'show_learning_card', arguments: { assetId: 'milk' } }]);
    expect(run).toHaveBeenCalledWith('model', expect.objectContaining({ tools: [tool] }), {});
  });

  it.each([
    [{ status: 429, message: 'Too many requests' }, 'rate_limited', true],
    [{ status: 503, message: 'Capacity unavailable' }, 'capacity', true],
    [{ status: 400, message: 'Bad request' }, 'provider_error', false],
  ] as const)('classifies provider failure %#', async (failure, code, retryable) => {
    const provider = new WorkersAIProvider({ ai: binding(async () => { throw failure; }), model: 'model' });
    await expect(provider.chat({ messages: [{ role: 'user', content: 'Hi' }] })).rejects.toMatchObject({ code, retryable });
  });

  it('enforces timeout and supports caller cancellation', async () => {
    const never = new Promise<unknown>(() => {});
    const provider = new WorkersAIProvider({ ai: binding(() => never), model: 'model', timeoutMs: 5 });
    await expect(provider.chat({ messages: [{ role: 'user', content: 'Hi' }] })).rejects.toMatchObject({ code: 'timeout' });
    const controller = new AbortController();
    controller.abort();
    await expect(provider.chat({ messages: [{ role: 'user', content: 'Hi' }], signal: controller.signal })).rejects.toBeInstanceOf(WorkersAIProviderError);
  });
});

describe('Workers AI Tutor bridge', () => {
  it('passes trusted lesson context and returns parsed turn with usage', async () => {
    const turn = { speech: 'Great!', subtitle: 'Great!', emotion: 'happy', gesture: 'clap', visual: { type: 'none' }, lessonAction: 'complete' };
    let capturedPayload: Record<string, unknown> | undefined;
    const run: WorkersAIBinding['run'] = async (_model, payload) => {
      capturedPayload = payload;
      return { response: JSON.stringify(turn), usage: { prompt_tokens: 20, completion_tokens: 9 } };
    };
    const provider = createWorkersAITurnProvider({ ai: binding(run), model: 'model' });
    const result = await provider.generateTurn({
      transcript: 'green', lessonId: 'colors',
      lessonContext: { stepId: 's1', outcome: 'correct', expectedAnswers: ['green'], hint: 'Grass is this color.', nextQuestionText: '', visualAssetId: 'color_green', matched: 'green', lessonAction: 'complete' },
      signal: new AbortController().signal,
    });
    expect(result).toEqual({ turn, usage: { llmInputTokens: 20, llmOutputTokens: 9, totalTokens: 29 } });
    const payload = capturedPayload as unknown as { messages: Array<{ content: string }> };
    expect(payload.messages[1]?.content).toContain('"lessonId":"colors"');
    expect(payload.messages[1]?.content).toContain('"outcome":"correct"');
  });

  it('routes complex questions to reasoning and retries ordinary failures on fallback', async () => {
    const models: string[] = [];
    const turn = { speech: 'Try this.', subtitle: 'Try this.', emotion: 'encouraging', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'retry' };
    const run: WorkersAIBinding['run'] = async (model) => {
      models.push(model);
      if (model === 'primary') throw { status: 503, message: 'capacity' };
      return { response: JSON.stringify(turn) };
    };
    const provider = createWorkersAIRoutedTurnProvider({ ai: binding(run), primaryModel: 'primary', fallbackModel: 'fallback', reasoningModel: 'reasoning' });
    const base = { lessonId: 'lesson', lessonContext: { stepId: 's1', outcome: 'unclear' as const, expectedAnswers: [], hint: '', nextQuestionText: '', visualAssetId: '', matched: '', lessonAction: 'retry' as const }, signal: new AbortController().signal };
    await provider.generateTurn({ ...base, transcript: 'apple' });
    await provider.generateTurn({ ...base, transcript: 'Can you explain why the moon changes shape?' });
    expect(models).toEqual(['primary', 'fallback', 'reasoning']);
  });
});
