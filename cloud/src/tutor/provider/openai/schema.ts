// Structured output: the model must answer with exactly a TutorTurn. Strict
// JSON schema (every property required, no extras) so a reply is either the
// shape below or a refusal; the Worker still runs validateTurn() on it.
import { EMOTIONS, GESTURES, LESSON_ACTIONS, VISUAL_TYPES } from '../../turn_validator';

export interface TurnSchemaOptions {
  /** Lesson turns pick from the shared enum; chat turns are pinned to "none". */
  lessonActions: readonly string[];
  /** Approved visual asset ids; "" means no card. */
  assetIds: readonly string[];
}

export function tutorTurnJsonSchema(opts: TurnSchemaOptions): Record<string, unknown> {
  return {
    type: 'object',
    additionalProperties: false,
    required: ['speech', 'emotion', 'gesture', 'visual', 'lessonAction', 'nextQuestion'],
    properties: {
      speech: { type: 'string', description: 'What Aliz says aloud. Short, simple English, ASCII only.' },
      emotion: { type: 'string', enum: [...EMOTIONS] },
      gesture: { type: 'string', enum: [...GESTURES] },
      visual: {
        type: 'object',
        additionalProperties: false,
        required: ['type', 'assetId'],
        properties: {
          type: { type: 'string', enum: [...VISUAL_TYPES] },
          assetId: { type: 'string', enum: ['', ...opts.assetIds], description: 'An approved card id, or "" when type is none.' },
        },
      },
      lessonAction: { type: 'string', enum: [...opts.lessonActions] },
      nextQuestion: { type: 'string', description: 'The next question when lessonAction is next_question, else "".' },
    },
  };
}

export const LESSON_TURN_ACTIONS: readonly string[] = LESSON_ACTIONS.filter((a) => a !== 'switch_lesson' && a !== 'jump_step');
export const CHAT_TURN_ACTIONS: readonly string[] = ['none'];

export function responseFormat(name: string, schema: Record<string, unknown>): Record<string, unknown> {
  return { type: 'json_schema', json_schema: { name, strict: true, schema } };
}
