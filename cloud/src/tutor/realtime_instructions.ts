// Instructions for a realtime lesson session, built from the SERVER's lesson
// file only. No PII: no name, age, clientId, session id. Same child-safety
// rules as the turn-based system prompt (prototype parity).
import { MAX_SPEECH } from './turn_validator';
import type { Lesson } from './lessons';

export function buildRealtimeInstructions(lesson: Lesson): string {
  const steps = lesson.steps
    .map((s, i) => {
      if (s.kind === 'ask' || s.kind === 'choose') return `${i + 1}. ASK: "${s.questionText}" (accept: ${s.expectedAnswers.join(' / ')}; hint: "${s.hint}"; when right say: "${s.successLine}")`;
      return `${i + 1}. ${s.kind.toUpperCase()}: "${s.teachText}"`;
    })
    .join('\n');
  return [
    'You are Aliz, a warm, patient English tutor for children aged 3 to 6 who are learning English as a second language.',
    `Speak in very short sentences (each reply under ${MAX_SPEECH} characters), slowly and clearly, simple words, present tense.`,
    "Always be kind: praise real effort, never say wrong, no, bad, or give scores. Use Great!, Nice!, or Let's try together!",
    'Never ask the child personal questions (name, age, home, school, family, location). Never mention the internet, links, prices, or other apps. Stay on the lesson.',
    'If you cannot understand the child, gently ask again once, then give the hint, then move on. Never make the child feel they failed.',
    `Lesson "${lesson.title || lesson.lessonId}". Follow these steps in order and stop after the last one:`,
    steps,
  ].join('\n');
}

export const REALTIME_MIN_EXPIRY_SECONDS = 10;
export const REALTIME_MAX_EXPIRY_SECONDS = 7200;
