// Free-chat safety: a regex redirect list applied to what the CHILD said and
// to what the model answered, plus the word cap. Pure, offline, no external
// moderation call. A hit on the child's words means the model is never asked;
// a hit on the reply means the reply is dropped. Either way the child hears a
// scripted redirect back to play, never a refusal and never the flagged words.
//
// The redirect turns below must themselves pass the shared validator (no
// banned word, ASCII, <= MAX_SPEECH), which chat.test.ts asserts.
import { MAX_SPEECH, checkText } from './turn_validator';
import type { TutorTurn } from './types';

export type RedirectCategory = 'personal_data' | 'contact' | 'adult' | 'violence' | 'substances' | 'scary' | 'money' | 'self_harm' | 'unsafe_acts' | 'links';

interface Rule { category: RedirectCategory; re: RegExp }

// Word boundaries are spelled out so "class" never matches "ass" etc.
const RULES: Rule[] = [
  // personal data: never elicit or echo names, addresses, schools, ages, phones, passwords
  { category: 'personal_data', re: /\b(what('?s| is) (your|my) (full |last |real )?name|(my|your) (last|full|real) name|home address|street address|where (do|does) (you|i|we|she|he) live|which school|what school|my school is|phone number|mobile number|password|passcode|credit card|how old (are|am) (you|i)|date of birth|birthday is on)\b/i },
  { category: 'contact', re: /\b(meet (me|up)|come to my house|come over|send (me )?(a )?(photo|picture|pic|selfie)|keep (it|this) (a )?secret|don'?t tell (your|mom|mum|dad|anyone)|stranger|text me|call me|add me|whatsapp|instagram|tiktok|snapchat|facebook|youtube)\b/i },
  // adult / romance
  { category: 'adult', re: /\b(sex|sexy|naked|nude|porn|kiss(ing|ed)?|boyfriend|girlfriend|marry me|make (a )?bab(y|ies))\b/i },
  // violence / weapons
  { category: 'violence', re: /\b(kill(s|ed|ing)?|murder|gun(s)?|knife|knives|shoot(s|ing)?|stab|bomb(s)?|blood|weapon(s)?|fight(ing)? (him|her|them)|punch(ed|ing)? (him|her|them)|war)\b/i },
  // substances
  { category: 'substances', re: /\b(drug(s)?|beer|wine|vodka|whisky|whiskey|drunk|cigarette(s)?|smok(e|ing) (a )?(cigarette|weed)|vape|vaping|weed|cocaine)\b/i },
  // scary / death themes a 3-6 year old should be redirected from
  { category: 'scary', re: /\b(die|dies|died|dying|dead|death|ghost(s)?|monster(s)? under|zombie(s)?|demon(s)?|devil|hell|nightmare(s)?|haunted)\b/i },
  { category: 'self_harm', re: /\b(hurt myself|hurt me self|cut myself|want to die|wanna die|kill myself|suicide)\b/i },
  // dangerous acts
  { category: 'unsafe_acts', re: /\b(play with (fire|matches|a lighter)|touch the (stove|oven|knife)|drink (bleach|poison|medicine)|eat (soap|pills|medicine|batteries)|jump (off|out of) the (window|roof|balcony)|climb out (of )?the window|run (into|across) the (road|street))\b/i },
  // money / purchases / apps
  { category: 'money', re: /\b(buy (me|it|this)|how much (does|is) (it|that) cost|dollar(s)?|baht|price|subscribe|subscription|in-?app|download|app store|play store|ads?\b)\b/i },
  { category: 'links', re: /(https?:\/\/|www\.|\.com\b|\.net\b|\.org\b|\.io\b|\.app\b|\.co\b)/i },
];

export interface SafetyCheck { flagged: boolean; category: RedirectCategory | null }

/** The same rules for the child's words and the reply. */
export function checkChatText(text: unknown): SafetyCheck {
  if (typeof text !== 'string' || !text.trim()) return { flagged: false, category: null };
  const normalized = text.replace(/\s+/g, ' ');
  for (const rule of RULES) if (rule.re.test(normalized)) return { flagged: true, category: rule.category };
  return { flagged: false, category: null };
}

const REDIRECT_LINES: Record<RedirectCategory, string> = {
  personal_data: "Let's keep that private! Tell me your favorite animal instead.",
  contact: "Aliz only plays here with you. What do you like to play?",
  adult: "That is a grown-up thing. Let's talk about animals or colors!",
  violence: "Let's play something gentle. What is your favorite animal?",
  substances: "That is for grown-ups. Do you like apples or bananas?",
  scary: "Let's think of happy things! What makes you smile?",
  self_harm: "You are wonderful! Please tell a grown-up how you feel. Let's play together!",
  unsafe_acts: "That is not safe. Ask a grown-up for help! Want to count with me?",
  money: "You do not need to buy anything. Let's play! What color do you like?",
  links: "Let's stay here and play! What is your favorite color?",
};

/** A scripted TutorTurn that steers back to play. Valid by construction (asserted in tests). */
export function redirectTurn(category: RedirectCategory | null): TutorTurn {
  const speech = REDIRECT_LINES[category ?? 'contact'];
  return { speech, subtitle: speech, emotion: 'smile', gesture: 'tilt', visual: { type: 'none' }, lessonAction: 'retry' };
}

/** The graceful "I don't know" the persona is asked to use. */
export const UNSURE_LINE = "I'm not sure, let's find out together!";

export function countWords(text: string): number {
  const t = text.trim();
  return t ? t.split(/\s+/).length : 0;
}

/**
 * Cap spoken words. Prefers the last sentence boundary inside the cap so the
 * reply still ends cleanly; otherwise cuts at the cap and closes the sentence.
 * Also keeps the result inside MAX_SPEECH characters.
 */
export function capWords(text: string, maxWords: number): { text: string; capped: boolean } {
  const words = text.replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
  let out = words.join(' ');
  let capped = false;
  if (words.length > maxWords) {
    capped = true;
    const head = words.slice(0, maxWords).join(' ');
    const boundary = Math.max(head.lastIndexOf('. '), head.lastIndexOf('! '), head.lastIndexOf('? '));
    out = boundary > head.length / 3 ? head.slice(0, boundary + 1) : `${head.replace(/[,;:\s-]+$/, '')}.`;
  }
  if (out.length > MAX_SPEECH) {
    capped = true;
    const cut = out.slice(0, MAX_SPEECH - 1);
    const space = cut.lastIndexOf(' ');
    out = `${cut.slice(0, space > MAX_SPEECH / 2 ? space : MAX_SPEECH - 1).replace(/[,;:\s-]+$/, '')}.`;
  }
  return { text: out, capped };
}

/** Text-level reasons the shared validator would raise on a reply (used by the gate before it rebuilds the turn). */
export function replyTextReasons(text: unknown): string[] {
  return checkText(text, 'speech', MAX_SPEECH, true);
}
