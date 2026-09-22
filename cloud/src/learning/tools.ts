export const EMOTIONS = ['neutral', 'happy', 'proud', 'excited', 'encouraging', 'thinking', 'listening', 'surprised', 'gentle', 'confused'] as const;
export const GESTURES = ['wave', 'nod', 'clap', 'thumbs_up', 'celebrate', 'encourage', 'thinking', 'listening'] as const;
export const TOOL_NAMES = ['show_learning_card', 'show_prop', 'set_emotion', 'play_gesture', 'look_at', 'award_star', 'start_minigame', 'suggest_activity', 'repeat_prompt', 'give_hint', 'complete_lesson'] as const;
export type ToolName = typeof TOOL_NAMES[number];
export type ToolCall = { name: ToolName; arguments: Record<string, unknown> };
export type ToolValidation = { ok: true; call: ToolCall } | { ok: false; reason: string };

const ID = /^[a-z0-9][a-z0-9_-]{0,63}$/;
const TARGETS = ['child', 'learning_card', 'prop', 'camera'] as const;
const RESULTS = ['mastered', 'completed', 'needs_practice', 'stopped'] as const;

function exact(args: Record<string, unknown>, keys: string[]): boolean { return Object.keys(args).every((key) => keys.includes(key)) && keys.every((key) => key in args); }
function id(value: unknown): value is string { return typeof value === 'string' && ID.test(value); }
function intensity(value: unknown): value is number { return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1; }

export function validateToolCall(input: unknown): ToolValidation {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { ok: false, reason: 'call:not_object' };
  const raw = input as { name?: unknown; arguments?: unknown };
  if (typeof raw.name !== 'string' || !(TOOL_NAMES as readonly string[]).includes(raw.name)) return { ok: false, reason: 'name:not_allowed' };
  if (!raw.arguments || typeof raw.arguments !== 'object' || Array.isArray(raw.arguments)) return { ok: false, reason: 'arguments:not_object' };
  const args = raw.arguments as Record<string, unknown>;
  let valid = false;
  switch (raw.name as ToolName) {
    case 'show_learning_card': valid = exact(args, ['assetId']) && id(args.assetId); break;
    case 'show_prop': valid = exact(args, ['assetId']) && id(args.assetId); break;
    case 'set_emotion': valid = exact(args, ['emotion', 'intensity']) && (EMOTIONS as readonly unknown[]).includes(args.emotion) && intensity(args.intensity); break;
    case 'play_gesture': valid = exact(args, ['gesture', 'intensity']) && (GESTURES as readonly unknown[]).includes(args.gesture) && intensity(args.intensity); break;
    case 'look_at': valid = exact(args, ['target']) && (TARGETS as readonly unknown[]).includes(args.target); break;
    case 'award_star': valid = exact(args, ['reason']) && id(args.reason); break;
    case 'start_minigame': valid = exact(args, ['activityId']) && id(args.activityId); break;
    case 'suggest_activity': valid = exact(args, ['activityId']) && id(args.activityId); break;
    case 'repeat_prompt': valid = exact(args, []); break;
    case 'give_hint': valid = exact(args, ['hintLevel']) && Number.isInteger(args.hintLevel) && (args.hintLevel as number) >= 1 && (args.hintLevel as number) <= 3; break;
    case 'complete_lesson': valid = exact(args, ['result']) && (RESULTS as readonly unknown[]).includes(args.result); break;
  }
  return valid ? { ok: true, call: { name: raw.name as ToolName, arguments: args } } : { ok: false, reason: 'arguments:invalid' };
}

export class ToolCallLimiter {
  private readonly calls: number[] = [];
  constructor(private readonly maximum = 8, private readonly windowMs = 60_000) {}
  allow(nowMs: number): boolean {
    while (this.calls.length && this.calls[0] <= nowMs - this.windowMs) this.calls.shift();
    if (this.calls.length >= this.maximum) return false;
    this.calls.push(nowMs);
    return true;
  }
}
