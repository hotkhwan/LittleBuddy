// Pure helpers for the parent portal. No DOM, no fetch: node:test imports this
// file directly (test/site.test.mjs), the browser imports it from portal.js.

/** Only loopback hosts may be called. Anything else is refused before fetch. */
export function isLoopbackUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return false;
  const host = url.hostname.toLowerCase();
  return host === "127.0.0.1" || host === "localhost" || host === "[::1]" || host === "::1";
}

/** Subject rule from cloud/src/util/validate.ts ID_RE. */
export const SUBJECT_RE = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;

/** Nickname rule from cloud/src/routes/accounts.ts (letters, digits, spaces, no contact details). */
export function nicknameProblem(nickname) {
  const value = String(nickname ?? "").trim();
  if (!value) return "Please type a nickname.";
  if (value.length > 24) return "Nicknames are at most 24 characters.";
  if (!/^[\p{L}\p{N} '._-]+$/u.test(value)) return "Use letters, digits and spaces only.";
  if (/@|https?:|www\./i.test(value)) return "A nickname must not contain contact details.";
  return null;
}

export const CONSENT_KINDS = ["privacy", "ai_tutor", "voice"];

export const CONSENT_LABELS = {
  privacy: { en: "Privacy notice read", th: "อ่านประกาศความเป็นส่วนตัวแล้ว" },
  ai_tutor: { en: "Allow the AI Tutor for this family", th: "อนุญาตให้ใช้ครูสอน AI สำหรับครอบครัวนี้" },
  voice: { en: "Allow voice lessons with the AI Tutor", th: "อนุญาตบทเรียนแบบพูดคุยด้วยเสียงกับครูสอน AI" },
};

/** "2 of 5 minutes" from a quota block; whole minutes, rounded up for used time. */
export function minutesSummary(quota) {
  const allowance = Math.max(0, Math.round((quota?.dailyAllowanceSeconds ?? 0) / 60));
  const used = Math.min(allowance, Math.ceil((quota?.usedSeconds ?? 0) / 60));
  const percent = allowance > 0 ? Math.min(100, Math.round((100 * (quota?.usedSeconds ?? 0)) / (allowance * 60))) : 0;
  return { used, allowance, percent, text: `${used} of ${allowance} minutes used today` };
}

export function initialFor(nickname) {
  const s = String(nickname ?? "").trim();
  return s ? Array.from(s)[0].toUpperCase() : "?";
}

/** Same JSON shapes as the Worker (docs/ALIZ_TUTOR_API.md 1.2), held in memory. */
export function createMockStore(nowMs = Date.now()) {
  const iso = (ms) => new Date(ms).toISOString();
  const state = {
    parentId: "mock-parent",
    children: [
      { childId: "mock-child-1", nickname: "Nong Mai", avatarId: "bunny", birthYearBucket: "2021-2022", locale: "th-TH", createdAt: iso(nowMs - 86400000 * 12) },
      { childId: "mock-child-2", nickname: "Bo", avatarId: "bear", birthYearBucket: "2019-2020", locale: "en-US", createdAt: iso(nowMs - 86400000 * 3) },
    ],
    consent: {
      privacy: { version: 1, grantedAt: iso(nowMs - 86400000 * 12), revokedAt: null, granted: true },
      ai_tutor: { version: 0, grantedAt: null, revokedAt: null, granted: false },
      voice: { version: 0, grantedAt: null, revokedAt: null, granted: false },
    },
    usedSeconds: { "mock-child-1": 130, "mock-child-2": 0 },
  };
  const nextUtcMidnight = () => {
    const d = new Date(nowMs);
    return iso(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1));
  };
  return {
    kind: "mock",
    async signIn(subject) {
      return { parentId: state.parentId, created: false, parentToken: `mock.${subject}`, expiresAt: iso(nowMs + 30 * 86400000), devMode: true };
    },
    async me() {
      return { parentId: state.parentId, provider: "dev", consentVersion: 1, createdAt: iso(nowMs - 86400000 * 12), via: "bearer" };
    },
    async children() {
      return { children: state.children.slice() };
    },
    async addChild(nickname) {
      const child = { childId: `mock-child-${state.children.length + 1}`, nickname, avatarId: null, birthYearBucket: null, locale: null, createdAt: iso(nowMs) };
      state.children.push(child);
      state.usedSeconds[child.childId] = 0;
      return child;
    },
    async consent() {
      return { parentId: state.parentId, requiredVersion: 1, consent: structuredClone(state.consent) };
    },
    async setConsent(kind, granted) {
      if (!CONSENT_KINDS.includes(kind)) throw new Error("unknown consent kind");
      state.consent[kind] = { version: 1, grantedAt: granted ? iso(nowMs) : state.consent[kind].grantedAt, revokedAt: granted ? null : iso(nowMs), granted };
      return { parentId: state.parentId, requiredVersion: 1, consent: structuredClone(state.consent) };
    },
    async quota(childId) {
      const used = state.usedSeconds[childId] ?? 0;
      return {
        clientId: null,
        childId,
        entitlement: "free",
        quota: { entitlement: "free", dailyAllowanceSeconds: 300, usedSeconds: used, remainingSeconds: Math.max(0, 300 - used), resetAtUtc: nextUtcMidnight(), dailyTurnAllowance: 60, usedTurns: Math.round(used / 10) },
        products: ["little_days.family_club.monthly", "little_days.family_club.yearly"],
        priceHint: { currency: "THB", monthly: 99, status: "proposed" },
      };
    },
    async entitlements() {
      return { parentId: state.parentId, entitlement: "free", activeUntil: null, source: "default", allowances: { free: { dailySeconds: 300, dailyTurns: 60 }, family_club: { dailySeconds: 1800, dailyTurns: 360 } }, products: [], billing: { enabled: false }, records: [] };
    },
  };
}

/** Human sentence for the subscription card. Billing is off everywhere today. */
export function subscriptionSummary(entitlements) {
  const billingOn = Boolean(entitlements?.billing?.enabled);
  const plan = entitlements?.entitlement === "family_club" ? "Family Club" : "Free";
  return {
    status: "not available",
    plan,
    text: billingOn ? `Plan: ${plan}. Subscriptions are not available yet.` : `Plan: ${plan}. Subscriptions are not available yet; billing is switched off on this server.`,
  };
}
