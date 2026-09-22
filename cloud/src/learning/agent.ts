import { CURRICULUM_BY_ID } from './curriculum';
import { ToolCallLimiter, validateToolCall, type ToolCall } from './tools';

export interface MasterySignal { skill: string; outcome: 'correct' | 'incorrect' | 'hinted'; at: string }
export interface RecentResponse { promptId: string; outcome: 'correct' | 'incorrect' | 'skipped' }
export interface AlizLearningAgentState {
  sessionId: string;
  childProfileId: string;
  lessonId: string;
  currentObjective: string;
  turn: number;
  masterySignals: MasterySignal[];
  recentResponses: RecentResponse[];
  availableTools: string[];
}

const SAFE_TOOLS = new Set(['show_learning_card', 'show_prop', 'set_emotion', 'play_gesture', 'look_at', 'award_star', 'start_minigame', 'suggest_activity', 'repeat_prompt', 'give_hint', 'complete_lesson']);
const UUIDISH = /^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$/;

/** Stateful but bounded lesson coordinator. Provider output can request semantic effects, never arbitrary execution. */
export class AlizLearningAgent {
  private readonly limiter: ToolCallLimiter;
  private state: AlizLearningAgentState;

  constructor(initial: AlizLearningAgentState, options: { maximumToolCallsPerMinute?: number } = {}) {
    this.state = validateState(initial);
    this.limiter = new ToolCallLimiter(options.maximumToolCallsPerMinute ?? 8);
  }

  snapshot(): AlizLearningAgentState { return structuredClone(this.state); }

  recordResponse(response: RecentResponse, signal?: MasterySignal): void {
    this.state.turn += 1;
    this.state.recentResponses = [...this.state.recentResponses.slice(-7), structuredClone(response)];
    if (signal) this.state.masterySignals = [...this.state.masterySignals.slice(-19), structuredClone(signal)];
  }

  requestTool(input: unknown, nowMs = Date.now()): { accepted: true; call: ToolCall } | { accepted: false; reason: string } {
    const result = validateToolCall(input);
    if (!result.ok) return { accepted: false, reason: result.reason };
    if (!this.state.availableTools.includes(result.call.name) || !SAFE_TOOLS.has(result.call.name)) return { accepted: false, reason: 'tool:not_available' };
    if (!this.limiter.allow(nowMs)) return { accepted: false, reason: 'tool:rate_limited' };
    if ((result.call.name === 'show_prop' || result.call.name === 'show_learning_card') && !this.allowedAsset(result.call.arguments.assetId as string)) return { accepted: false, reason: 'asset:not_in_lesson' };
    return { accepted: true, call: result.call };
  }

  private allowedAsset(assetId: string): boolean { return CURRICULUM_BY_ID.get(this.state.lessonId)?.learningProps.includes(assetId) ?? false; }
}

export function validateState(input: AlizLearningAgentState): AlizLearningAgentState {
  if (!UUIDISH.test(input.sessionId) || !UUIDISH.test(input.childProfileId)) throw new Error('Invalid learning agent identity.');
  const lesson = CURRICULUM_BY_ID.get(input.lessonId);
  if (!lesson?.active) throw new Error('Learning agent lesson is not approved and active.');
  if (input.currentObjective !== lesson.learningObjective) throw new Error('Learning objective must come from the approved lesson.');
  if (!Number.isInteger(input.turn) || input.turn < 0) throw new Error('Invalid learning agent turn.');
  const availableTools = [...new Set(input.availableTools)];
  if (availableTools.some((tool) => !SAFE_TOOLS.has(tool))) throw new Error('Learning agent tool is not allowed.');
  return structuredClone({ ...input, masterySignals: input.masterySignals.slice(-20), recentResponses: input.recentResponses.slice(-8), availableTools });
}

/** Prevents accidental key collisions when an external state store is added. */
export function stateStorageKey(parentId: string, childProfileId: string, sessionId: string): string {
  for (const value of [parentId, childProfileId, sessionId]) if (!UUIDISH.test(value)) throw new Error('Invalid state key component.');
  return `learning:${parentId}:${childProfileId}:${sessionId}`;
}
