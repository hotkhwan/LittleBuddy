// The free-chat half of the provider contract, kept OUT of
// provider_interface.ts (Agent D's lesson contract is unchanged): a turn
// provider MAY also implement `generateChatTurn`; the session DO discovers it
// by duck typing and otherwise answers from the deterministic mock below.
//
// Also here: the chat gate every reply goes through (shared validator ->
// safety regex -> word cap -> `lessonAction: "none"` on the wire) and the
// mock chat provider (scripted, follow-up aware, no key, no network).
import type { ProviderTurnResult, TurnProvider, TurnUsage } from './provider_interface';
import { MAX_SPEECH, validateTurn } from './turn_validator';
import type { TutorTurn } from './types';
import { UNSURE_LINE, capWords, checkChatText, redirectTurn, type RedirectCategory } from './chat_safety';

export interface ChatMessage { role: 'child' | 'tutor'; text: string }

export interface ChatTurnInput {
  transcript: string;            // <= 500 chars; the child's words (the ONLY free text from the device)
  history: ChatMessage[];        // rolling window, oldest first, already trimmed to K exchanges
  responseMaxWords: number;      // spoken-word cap for this reply (8..40)
  signal: AbortSignal;
}

export interface ChatTurnProvider {
  readonly name: string;
  generateChatTurn(input: ChatTurnInput): Promise<ProviderTurnResult>;
}

/** The chat reply as it leaves the Worker: a TutorTurn whose lessonAction is "none". */
export type ChatTurn = Omit<TutorTurn, 'lessonAction'> & { lessonAction: 'none' };

export function chatProviderOf(provider: TurnProvider | null | undefined): ChatTurnProvider | null {
  const p = provider as unknown as Partial<ChatTurnProvider> | null | undefined;
  return p && typeof p.generateChatTurn === 'function' ? (p as ChatTurnProvider) : null;
}

export interface ChatGateResult {
  ok: boolean;
  turn: ChatTurn;                // the reply to send: the gated candidate, or a redirect
  reasons: string[];             // why the candidate was replaced (empty when ok)
  capped: boolean;               // the speech was shortened to the word cap
  redirected: RedirectCategory | null;
}

/**
 * Every chat reply, from any provider, goes through here. The shared
 * validator rules apply to speech/subtitle/emotion/gesture/visual exactly as
 * for a lesson turn (the enum member `none` is not part of that shared
 * contract, so the candidate is validated with `retry` in its place and
 * `none` is put back on the wire afterwards; the Godot controller maps it
 * back to `retry`, "keep listening", before its own validator).
 */
export function gateChatTurn(candidate: unknown, opts: { responseMaxWords: number; allowlist?: readonly string[] }): ChatGateResult {
  const c = candidate && typeof candidate === 'object' && !Array.isArray(candidate) ? { ...(candidate as Record<string, unknown>) } : null;
  if (!c) return { ok: false, turn: toChatTurn(redirectTurn(null)), reasons: ['turn:not_object'], capped: false, redirected: null };
  // The word cap is a normalisation, not a rejection: cap first so a wordy but
  // otherwise safe answer is shortened, then validate what would be spoken.
  let capped = false;
  if (typeof c.speech === 'string') {
    const r = capWords(c.speech, opts.responseMaxWords);
    capped = r.capped;
    c.speech = r.text;
    c.subtitle = r.text;
  }
  delete c.nextQuestion;
  if (c.lessonAction === undefined || c.lessonAction === 'none') c.lessonAction = 'retry';
  const v = validateTurn(c, { allowlist: opts.allowlist });
  if (!v.ok) return { ok: false, turn: toChatTurn(redirectTurn(null)), reasons: v.reasons, capped, redirected: null };
  const safety = checkChatText(`${v.turn.speech} ${v.turn.subtitle}`);
  if (safety.flagged) return { ok: false, turn: toChatTurn(redirectTurn(safety.category)), reasons: [`reply:redirect:${safety.category}`], capped, redirected: safety.category };
  return { ok: true, turn: toChatTurn(v.turn), reasons: [], capped, redirected: null };
}

export function toChatTurn(turn: TutorTurn): ChatTurn {
  const { nextQuestion: _dropped, ...rest } = turn;
  return { ...rest, lessonAction: 'none' };
}

// ---------------------------------------------------------------- mock chat
// Deterministic, offline. Answers simple 3-6 year old questions about a
// small set of topics, remembers the last topic for follow-ups ("and dogs?",
// "why?"), says the unsure line for anything else, and never exceeds the cap.
interface Topic { keys: string[]; name: string; facts: string[]; asset?: string }

const TOPICS: Topic[] = [
  { keys: ['cat', 'cats', 'kitty', 'kitten'], name: 'cats', asset: 'cat', facts: ['Cats eat cat food and drink water.', 'Cats say meow and love to nap in the sun.', 'A baby cat is a kitten. Kittens love to play!'] },
  { keys: ['dog', 'dogs', 'puppy', 'doggy'], name: 'dogs', asset: 'dog', facts: ['Dogs eat dog food and love bones.', 'Dogs say woof and wag their tails when happy.', 'A baby dog is a puppy. Puppies love to run!'] },
  { keys: ['apple', 'apples'], name: 'apples', asset: 'apple_red', facts: ['Apples grow on trees. They can be red or green.', 'Apples are sweet and crunchy. Yum!', 'You can make apple juice from apples.'] },
  { keys: ['banana', 'bananas'], name: 'bananas', asset: 'banana_yellow', facts: ['Bananas are yellow and soft inside.', 'Monkeys love bananas, and so do I!', 'Bananas grow in big bunches on tall plants.'] },
  { keys: ['red', 'blue', 'yellow', 'green', 'color', 'colour', 'colors', 'colours'], name: 'colors', facts: ['Red like an apple, blue like the sky, yellow like the sun!', 'Mixing blue and yellow makes green.', 'The sky is blue on a sunny day.'] },
  { keys: ['sun', 'sunny', 'sky', 'moon', 'star', 'stars'], name: 'the sky', facts: ['The sun is a big warm star. It gives us light.', 'At night we can see the moon and the stars.', 'Clouds float in the sky. Some look like animals!'] },
  { keys: ['rain', 'rainy', 'water', 'wet'], name: 'rain', facts: ['Rain is water falling from clouds.', 'Plants drink the rain to grow big.', 'After the rain you might see a rainbow!'] },
  { keys: ['one', 'two', 'three', 'count', 'counting', 'number', 'numbers'], name: 'counting', facts: ['One, two, three! Can you count with me?', 'Two hands, ten fingers. Let us count them!', 'Three is one more than two.'] },
  { keys: ['song', 'sing', 'music', 'dance'], name: 'music', facts: ['I love to sing! La la la. Do you like to dance?', 'Music makes me want to clap my hands.', 'We can sing about the sun and the rain.'] },
  { keys: ['friend', 'friends', 'play', 'game', 'toy', 'toys'], name: 'playing', facts: ['Playing with friends is so much fun!', 'We can play a color game. Say a color!', 'Toys are for sharing. That is kind.'] },
];

const GREETINGS = /\b(hi|hello|hey|good morning|good night)\b/i;
const HOW_ARE_YOU = /\bhow are you\b/i;
const FOLLOW_UP = /^\s*(and|what about|how about|why|why not|more|tell me more|again|really)\b/i;
const THANKS = /\b(thank you|thanks)\b/i;

function topicIn(text: string): Topic | null {
  const said = ` ${text.toLowerCase().replace(/[^a-z ]/g, ' ')} `;
  for (const t of TOPICS) if (t.keys.some((k) => said.includes(` ${k} `))) return t;
  return null;
}

export function createMockChatProvider(opts: { allowlist?: readonly string[] } = {}): ChatTurnProvider {
  const allowlist = new Set(opts.allowlist ?? []);
  return {
    name: 'mock',
    async generateChatTurn({ transcript, history, responseMaxWords }: ChatTurnInput): Promise<ProviderTurnResult> {
      const said = transcript.trim();
      let topic = topicIn(said);
      let fromContext = false;
      if (!topic && FOLLOW_UP.test(said)) {
        for (let i = history.length - 1; i >= 0 && !topic; i -= 1) topic = topicIn(history[i].text);
        fromContext = Boolean(topic);
      }
      let speech: string;
      let emotion: TutorTurn['emotion'] = 'smile';
      let gesture: TutorTurn['gesture'] = 'nod';
      let asset = '';
      if (topic) {
        // Deterministic: the n-th time this topic comes up in the window gets its n-th fact.
        const seen = history.filter((m) => m.role === 'child' && topicIn(m.text) === topic).length;
        const fact = topic.facts[seen % topic.facts.length];
        speech = fromContext ? `About ${topic.name}? ${fact}` : fact;
        emotion = 'happy';
        gesture = fromContext ? 'point' : 'nod';
        asset = topic.asset && (allowlist.size === 0 || allowlist.has(topic.asset)) ? topic.asset : '';
      } else if (HOW_ARE_YOU.test(said)) {
        speech = 'I am happy today! How are you?';
        emotion = 'happy';
        gesture = 'wave';
      } else if (GREETINGS.test(said)) {
        speech = 'Hello! I am Aliz. What do you want to talk about?';
        emotion = 'happy';
        gesture = 'wave';
      } else if (THANKS.test(said)) {
        speech = 'You are welcome! What else do you want to know?';
        emotion = 'happy';
        gesture = 'clap';
      } else if (!said) {
        speech = 'I am listening! Tell me anything.';
        emotion = 'listening';
        gesture = 'tilt';
      } else {
        speech = `${UNSURE_LINE} Do you like cats or dogs?`;
        emotion = 'thinking';
        gesture = 'tilt';
      }
      const capped = capWords(speech, Math.max(1, Math.min(responseMaxWords, MAX_SPEECH))).text;
      const turn: Record<string, unknown> = {
        speech: capped, subtitle: capped, emotion, gesture,
        visual: asset ? { type: 'flashcard', assetId: asset } : { type: 'none' },
        lessonAction: 'none',
      };
      const usage: TurnUsage = { llmInputTokens: 0, llmOutputTokens: 0 };
      return { turn, usage };
    },
  };
}
