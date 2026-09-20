// Usage + cost accounting. Per turn: sttSeconds, llmInputTokens,
// llmOutputTokens, ttsChars, latencyMs, cached, costUsd. Per session totals.
// Cost estimates come from config/prices.json (cited source inside the file);
// a null price contributes 0 and is reported as `priceMissing`.
// Also hosts the monthly budget guard (MONTHLY_BUDGET_USD, UTC month).
import fs from 'node:fs';

export const USAGE_FIELDS = Object.freeze(['sttSeconds', 'llmInputTokens', 'llmOutputTokens', 'cachedInputTokens', 'ttsChars', 'latencyMs']);

/** @param {string} pricesPath */
export function loadPrices(pricesPath) {
  try {
    return JSON.parse(fs.readFileSync(pricesPath, 'utf8'));
  } catch {
    return { llm: {}, stt: {}, tts: {} };
  }
}

/**
 * Pure per-turn cost arithmetic.
 * @param {{sttSeconds?: number, llmInputTokens?: number, llmOutputTokens?: number, cachedInputTokens?: number, ttsChars?: number, realtimeAudioInputTokens?: number, realtimeCachedAudioInputTokens?: number, realtimeAudioOutputTokens?: number, realtimeTextInputTokens?: number, realtimeCachedTextInputTokens?: number, realtimeTextOutputTokens?: number}} u
 * @param {{prices: any, model: string, sttModel?: string, ttsModel?: string, sttMode: 'device'|'cloud', ttsMode: 'device'|'cloud', realtimeModel?: string}} p
 * @returns {{costUsd: number, breakdown: {stt: number, llmInput: number, llmOutput: number, tts: number, realtime: number}, priceMissing: string[]}}
 */
export function estimateTurnCost(u, p) {
  const missing = [];
  let realtime = 0;
  const rtIn = num(u.realtimeAudioInputTokens), rtOut = num(u.realtimeAudioOutputTokens), rtTin = num(u.realtimeTextInputTokens), rtTout = num(u.realtimeTextOutputTokens);
  if (rtIn || rtOut || rtTin || rtTout) {
    const rt = p.prices?.realtime?.[p.realtimeModel ?? ''];
    if (!rt || !isNum(rt.audioInputPer1MTokens) || !isNum(rt.audioOutputPer1MTokens)) missing.push(`realtime:${p.realtimeModel}`);
    else {
      const cachedIn = Math.min(num(u.realtimeCachedAudioInputTokens), rtIn);
      const cachedTin = Math.min(num(u.realtimeCachedTextInputTokens), rtTin);
      realtime = ((rtIn - cachedIn) / 1e6) * rt.audioInputPer1MTokens
        + (cachedIn / 1e6) * (isNum(rt.cachedAudioInputPer1MTokens) ? rt.cachedAudioInputPer1MTokens : rt.audioInputPer1MTokens)
        + (rtOut / 1e6) * rt.audioOutputPer1MTokens
        + ((rtTin - cachedTin) / 1e6) * (isNum(rt.textInputPer1MTokens) ? rt.textInputPer1MTokens : 0)
        + (cachedTin / 1e6) * (isNum(rt.cachedTextInputPer1MTokens) ? rt.cachedTextInputPer1MTokens : 0)
        + (rtTout / 1e6) * (isNum(rt.textOutputPer1MTokens) ? rt.textOutputPer1MTokens : 0);
    }
  }
  const llm = p.prices?.llm?.[p.model];
  const stt = p.prices?.stt?.[p.sttModel];
  const tts = p.prices?.tts?.[p.ttsModel];

  const inTok = num(u.llmInputTokens);
  const cachedTok = Math.min(num(u.cachedInputTokens), inTok);
  const freshTok = inTok - cachedTok;
  const outTok = num(u.llmOutputTokens);

  let llmInput = 0;
  let llmOutput = 0;
  if (inTok || outTok) {
    if (!llm || !isNum(llm.inputPer1MTokens) || !isNum(llm.outputPer1MTokens)) missing.push(`llm:${p.model}`);
    else {
      const cachedRate = isNum(llm.cachedInputPer1MTokens) ? llm.cachedInputPer1MTokens : llm.inputPer1MTokens;
      llmInput = (freshTok / 1e6) * llm.inputPer1MTokens + (cachedTok / 1e6) * cachedRate;
      llmOutput = (outTok / 1e6) * llm.outputPer1MTokens;
    }
  }

  let sttCost = 0;
  const sttSeconds = num(u.sttSeconds);
  if (p.sttMode === 'cloud' && sttSeconds > 0) {
    if (!stt || !isNum(stt.perMinute)) missing.push(`stt:${p.sttModel}`);
    else sttCost = (sttSeconds / 60) * stt.perMinute;
  }

  let ttsCost = 0;
  const ttsChars = num(u.ttsChars);
  if (p.ttsMode === 'cloud' && ttsChars > 0) {
    if (!tts || !isNum(tts.per1MChars)) missing.push(`tts:${p.ttsModel}`);
    else ttsCost = (ttsChars / 1e6) * tts.per1MChars;
  }

  const total = sttCost + llmInput + llmOutput + ttsCost + realtime;
  return {
    costUsd: round8(total),
    breakdown: { stt: round8(sttCost), llmInput: round8(llmInput), llmOutput: round8(llmOutput), tts: round8(ttsCost), realtime: round8(realtime) },
    priceMissing: missing,
  };
}

/** @param {number} nowMs */
export function utcMonthKey(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 7);
}

/**
 * @param {{store: ReturnType<import('./store.js').createStore>, config: import('./config.js').Config, now: () => number, prices?: any}} deps
 */
export function createUsage({ store, config, now, prices }) {
  const priceTable = prices ?? loadPrices(config.pricesPath);
  const pricing = { prices: priceTable, model: config.model, sttModel: config.sttModel, ttsModel: config.ttsModel, sttMode: config.sttMode, ttsMode: config.ttsMode, realtimeModel: config.realtimeModel };

  /**
   * Record one turn's usage against a session and the monthly spend ledger.
   * @param {string} sessionId
   * @param {number} turnIndex
   * @param {{sttSeconds?: number, clientReportedAudioSeconds?: number, llmInputTokens?: number, llmOutputTokens?: number, cachedInputTokens?: number, ttsChars?: number, latencyMs?: number, cached?: boolean, provider?: string, realtime?: Record<string, number>}} u
   * `sttSeconds` is only non-zero when the SERVER ran speech recognition (none
   * today); `clientReportedAudioSeconds` is informational and never costed (finding L4).
   */
  function recordTurn(sessionId, turnIndex, u) {
    const cost = estimateTurnCost({ ...u, ...(u.realtime ?? {}) }, pricing);
    const entry = {
      sessionId,
      turnIndex,
      at: new Date(now()).toISOString(),
      sttSeconds: num(u.sttSeconds),
      clientReportedAudioSeconds: num(u.clientReportedAudioSeconds),
      llmInputTokens: num(u.llmInputTokens),
      llmOutputTokens: num(u.llmOutputTokens),
      cachedInputTokens: num(u.cachedInputTokens),
      ttsChars: num(u.ttsChars),
      latencyMs: Math.round(num(u.latencyMs)),
      cached: Boolean(u.cached),
      provider: u.provider ?? 'unknown',
      costUsd: cost.costUsd,
      costBreakdown: cost.breakdown,
      priceMissing: cost.priceMissing,
      realtime: u.realtime ? Object.fromEntries(Object.entries(u.realtime).map(([k, v]) => [k, num(v)])) : undefined,
    };
    store.turns.set(`${sessionId}:${turnIndex}`, entry);
    addSpend(cost.costUsd);
    return entry;
  }

  /** @param {number} usd */
  function addSpend(usd) {
    const key = utcMonthKey(now());
    const rec = store.spend.get(key) ?? { monthKey: key, spentUsd: 0, turns: 0 };
    rec.spentUsd = round8(rec.spentUsd + usd);
    rec.turns += 1;
    store.spend.set(key, rec);
    return rec;
  }

  function monthlySpend() {
    const key = utcMonthKey(now());
    return store.spend.get(key) ?? { monthKey: key, spentUsd: 0, turns: 0 };
  }

  /** True when the month's estimated spend has reached the (always configured) budget. */
  function budgetExceeded() {
    return monthlySpend().spentUsd >= config.monthlyBudgetUsd;
  }

  /** @param {string} sessionId */
  function sessionTotals(sessionId) {
    const totals = { turns: 0, sttSeconds: 0, llmInputTokens: 0, llmOutputTokens: 0, cachedInputTokens: 0, ttsChars: 0, latencyMs: 0, cachedTurns: 0, costUsd: 0 };
    for (const t of store.turns.values()) {
      if (t.sessionId !== sessionId) continue;
      totals.turns += 1;
      totals.sttSeconds += t.sttSeconds;
      totals.llmInputTokens += t.llmInputTokens;
      totals.llmOutputTokens += t.llmOutputTokens;
      totals.cachedInputTokens += t.cachedInputTokens;
      totals.ttsChars += t.ttsChars;
      totals.latencyMs += t.latencyMs;
      totals.cachedTurns += t.cached ? 1 : 0;
      totals.costUsd = round8(totals.costUsd + t.costUsd);
    }
    return totals;
  }

  return { recordTurn, sessionTotals, monthlySpend, budgetExceeded, pricing, estimate: (u) => estimateTurnCost(u, pricing) };
}

/** @param {unknown} v */
function num(v) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : 0;
}
/** @param {unknown} v */
function isNum(v) {
  return typeof v === 'number' && Number.isFinite(v);
}
/** @param {number} n */
function round8(n) {
  return Math.round(n * 1e8) / 1e8;
}
