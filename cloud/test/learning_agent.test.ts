import { describe, expect, it } from 'vitest';
import { AlizLearningAgent, CURRICULUM_BY_ID, stateStorageKey, validateState, validateToolCall, type AlizLearningAgentState } from '../src/learning';

function state(overrides: Partial<AlizLearningAgentState> = {}): AlizLearningAgentState {
  const lesson = CURRICULUM_BY_ID.get('en-prek-colors-look-touch-v1')!;
  return { sessionId: 'session_123', childProfileId: 'child_123', lessonId: lesson.id, currentObjective: lesson.learningObjective, turn: 0, masterySignals: [], recentResponses: [], availableTools: ['show_learning_card', 'set_emotion', 'give_hint', 'complete_lesson'], ...overrides };
}

describe('Aliz semantic tool boundary', () => {
  it('accepts only exact whitelisted schemas and lesson-owned assets', () => {
    const agent = new AlizLearningAgent(state());
    expect(agent.requestTool({ name: 'show_learning_card', arguments: { assetId: 'color_green' } }, 1).accepted).toBe(true);
    expect(agent.requestTool({ name: 'show_learning_card', arguments: { assetId: 'external_url' } }, 2)).toEqual({ accepted: false, reason: 'asset:not_in_lesson' });
    expect(agent.requestTool({ name: 'shell', arguments: { command: 'whoami' } }, 3)).toEqual({ accepted: false, reason: 'name:not_allowed' });
    expect(validateToolCall({ name: 'set_emotion', arguments: { emotion: 'happy', intensity: 2 } })).toEqual({ ok: false, reason: 'arguments:invalid' });
    expect(validateToolCall({ name: 'repeat_prompt', arguments: { hidden: true } })).toEqual({ ok: false, reason: 'arguments:invalid' });
  });

  it('rate-limits accepted calls and bounds retained state', () => {
    const agent = new AlizLearningAgent(state(), { maximumToolCallsPerMinute: 2 });
    const call = { name: 'give_hint', arguments: { hintLevel: 1 } };
    expect(agent.requestTool(call, 100).accepted).toBe(true);
    expect(agent.requestTool(call, 101).accepted).toBe(true);
    expect(agent.requestTool(call, 102)).toEqual({ accepted: false, reason: 'tool:rate_limited' });
    for (let i = 0; i < 30; i += 1) agent.recordResponse({ promptId: `p${i}`, outcome: 'correct' }, { skill: 'colors', outcome: 'correct', at: new Date(i * 1000).toISOString() });
    expect(agent.snapshot().recentResponses).toHaveLength(8);
    expect(agent.snapshot().masterySignals).toHaveLength(20);
  });

  it('restores only approved state and namespaces account/profile/session isolation', () => {
    expect(validateState(state()).lessonId).toBe('en-prek-colors-look-touch-v1');
    expect(() => validateState(state({ lessonId: 'draft_lesson' }))).toThrow(/approved/);
    expect(() => validateState(state({ availableTools: ['fetch_url'] }))).toThrow(/not allowed/);
    expect(stateStorageKey('parent_a', 'child_a', 'session_a')).not.toBe(stateStorageKey('parent_a', 'child_b', 'session_a'));
    expect(stateStorageKey('parent_a', 'child_a', 'session_a')).not.toBe(stateStorageKey('parent_b', 'child_a', 'session_a'));
  });
});
