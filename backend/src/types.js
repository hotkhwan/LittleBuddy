// JSDoc-only type definitions shared across modules. No runtime code.

/**
 * @typedef {Object} TutorTurn
 * @property {string} speech
 * @property {string} [subtitle]
 * @property {'neutral'|'listening'|'thinking'|'happy'|'encouraging'|'smile'} emotion
 * @property {'none'|'nod'|'tilt'|'point'|'clap'|'wave'} gesture
 * @property {{type: 'none'|'flashcard'|'model', assetId?: string}} visual
 * @property {'next_question'|'retry'|'give_hint'|'complete'|'end_session'} lessonAction
 * @property {string} [nextQuestion]
 */

/**
 * @typedef {Object} LessonContext
 * @property {string} stepId
 * @property {'correct'|'incorrect'|'unclear'} outcome
 * @property {string[]} [expectedAnswers]
 * @property {string} [hint]
 * @property {string} [nextQuestionText]
 * @property {string} [visualAssetId]
 * @property {string} [matched]
 * @property {string} [lessonAction]
 */

/**
 * @typedef {Object} ProviderResult
 * @property {Record<string, unknown>} turn raw (unvalidated) turn
 * @property {{llmInputTokens: number, llmOutputTokens: number, cachedInputTokens?: number}} usage
 */

/**
 * @typedef {Object} ConversationProvider
 * @property {string} name
 * @property {(input: {transcript: string, lessonId: string, lessonContext: LessonContext, signal?: AbortSignal}) => Promise<ProviderResult>} generateTurn
 */

/**
 * @typedef {Object} RequestContext
 * @property {string} method
 * @property {URL} url
 * @property {Record<string, string>} params
 * @property {Record<string, string>} headers
 * @property {any} body
 * @property {string} ip
 * @property {AbortSignal} signal
 */

/**
 * @typedef {Object} Response
 * @property {number} status
 * @property {unknown} body
 * @property {Record<string, string>} [headers]
 */

export {};
