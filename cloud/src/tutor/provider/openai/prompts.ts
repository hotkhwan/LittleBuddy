// System prompts, built SERVER side from trusted context only. The child's
// transcript is the sole free text and travels in the user message, quoted as
// data. No name, age, clientId or session id ever appears here.
import { MAX_NEXT_QUESTION, MAX_SPEECH } from '../../turn_validator';
import type { LessonContext } from '../../types';
import type { ChatMessage } from '../../chat_provider';
import { UNSURE_LINE } from '../../chat_safety';

const COMMON_RULES = [
  'You are Aliz, a kind, playful English teacher for a child aged 3 to 6 who is learning English as a second language.',
  `Speak in very short, simple sentences (each reply under ${MAX_SPEECH} characters), present tense, everyday words, ASCII letters only, no emoji.`,
  "Always be warm: praise real effort, never say wrong, no, bad, stupid, or give scores. Use Great!, Nice!, or Let's try together!",
  'Never ask for or repeat personal information: no name, age, home, address, school, phone, family details or location.',
  'Never mention the internet, links, prices, purchases, other apps, or that you are an AI.',
  'If a topic is unsafe, scary, adult, violent, about drugs or alcohol, or about personal data, gently redirect to play or the lesson in one friendly sentence.',
  'Answer ONLY with the JSON object described by the schema.',
];

function jsonLine(label: string, value: unknown): string {
  return `${label}: ${JSON.stringify(value)}`;
}

export function buildLessonSystemPrompt(lessonId: string, ctx: LessonContext): string {
  const lines = [
    ...COMMON_RULES,
    `You are running lesson "${lessonId}", step "${ctx.stepId}". The device already judged the answer: outcome = ${ctx.outcome}.`,
    'Follow the outcome exactly. correct: praise and, if a next question is given, ask it with lessonAction next_question (or complete when there is none). incorrect: encourage and give the hint with lessonAction give_hint. unclear: kindly ask the child to say it once more with lessonAction retry.',
    `Only the given visualAssetId may be shown as a flashcard, otherwise visual.type must be none. nextQuestion is at most ${MAX_NEXT_QUESTION} characters and only when lessonAction is next_question.`,
    jsonLine('expectedAnswers', ctx.expectedAnswers),
    jsonLine('hint', ctx.hint),
    jsonLine('nextQuestionText', ctx.nextQuestionText),
    jsonLine('visualAssetId', ctx.visualAssetId),
    jsonLine('successLine', ctx.successLine ?? ''),
    jsonLine('answerLine', ctx.answerLine ?? ''),
    jsonLine('suggestedLessonAction', ctx.lessonAction),
  ];
  return lines.join('\n');
}

export function buildChatSystemPrompt(responseMaxWords: number, assetIds: readonly string[]): string {
  return [
    ...COMMON_RULES,
    `This is free conversation, not a lesson. Answer the child's question or comment in at most ${responseMaxWords} words.`,
    `If you are not sure, say exactly: "${UNSURE_LINE}" and offer a simple related idea.`,
    'You may end with ONE short, simple follow-up question to keep the child talking. Stay on child-friendly topics: animals, colors, food, weather, counting, songs, play.',
    `If a card from this list fits the topic you may show it as a flashcard: ${assetIds.join(', ')}. Otherwise visual.type is none.`,
    'lessonAction is always "none" and nextQuestion is always "".',
  ].join('\n');
}

/** The user message for a lesson turn: the transcript quoted as data. */
export function lessonUserMessage(transcript: string): string {
  return `The child said (transcript, may be empty or misheard): ${JSON.stringify(transcript)}`;
}

/** Chat: the rolling window as prior messages, then the new transcript. */
export function chatMessages(history: ChatMessage[], transcript: string): Array<{ role: 'user' | 'assistant'; content: string }> {
  const out: Array<{ role: 'user' | 'assistant'; content: string }> = [];
  for (const m of history) out.push({ role: m.role === 'child' ? 'user' : 'assistant', content: m.text });
  out.push({ role: 'user', content: transcript });
  return out;
}
