// Per-turn cost estimate in USD micro-units, from the bundled list prices
// (cloud/config/prices.json, copied from the prototype with its source URL and
// fetch date). A missing price contributes 0 and is reported, never invented.
import prices from '../../config/prices.json';

type PriceTable = typeof prices;

export interface CostUsage {
  llmInputTokens?: number;
  llmOutputTokens?: number;
  cachedInputTokens?: number;
  realtimeAudioInputTokens?: number;
  realtimeCachedAudioInputTokens?: number;
  realtimeAudioOutputTokens?: number;
  realtimeTextInputTokens?: number;
  realtimeCachedTextInputTokens?: number;
  realtimeTextOutputTokens?: number;
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : 0;
}
function isNum(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

export function estimateCostMicro(u: CostUsage, models: { model: string; realtimeModel: string }, table: PriceTable = prices): { costUsdMicro: number; priceMissing: string[] } {
  const missing: string[] = [];
  let usd = 0;
  const llm = (table.llm as unknown as Record<string, { inputPer1MTokens?: number; cachedInputPer1MTokens?: number; outputPer1MTokens?: number }>)[models.model];
  const inTok = num(u.llmInputTokens);
  const outTok = num(u.llmOutputTokens);
  if (inTok || outTok) {
    if (!llm || !isNum(llm.inputPer1MTokens) || !isNum(llm.outputPer1MTokens)) missing.push(`llm:${models.model}`);
    else {
      const cached = Math.min(num(u.cachedInputTokens), inTok);
      const cachedRate = isNum(llm.cachedInputPer1MTokens) ? llm.cachedInputPer1MTokens : llm.inputPer1MTokens;
      usd += ((inTok - cached) / 1e6) * llm.inputPer1MTokens + (cached / 1e6) * cachedRate + (outTok / 1e6) * llm.outputPer1MTokens;
    }
  }
  const rtIn = num(u.realtimeAudioInputTokens), rtOut = num(u.realtimeAudioOutputTokens), rtTin = num(u.realtimeTextInputTokens), rtTout = num(u.realtimeTextOutputTokens);
  if (rtIn || rtOut || rtTin || rtTout) {
    const rt = (table.realtime as unknown as Record<string, Record<string, unknown>>)[models.realtimeModel];
    if (!rt || !isNum(rt.audioInputPer1MTokens) || !isNum(rt.audioOutputPer1MTokens)) missing.push(`realtime:${models.realtimeModel}`);
    else {
      const cachedIn = Math.min(num(u.realtimeCachedAudioInputTokens), rtIn);
      const cachedTin = Math.min(num(u.realtimeCachedTextInputTokens), rtTin);
      usd += ((rtIn - cachedIn) / 1e6) * rt.audioInputPer1MTokens
        + (cachedIn / 1e6) * (isNum(rt.cachedAudioInputPer1MTokens) ? rt.cachedAudioInputPer1MTokens : rt.audioInputPer1MTokens)
        + (rtOut / 1e6) * rt.audioOutputPer1MTokens
        + ((rtTin - cachedTin) / 1e6) * (isNum(rt.textInputPer1MTokens) ? rt.textInputPer1MTokens : 0)
        + (cachedTin / 1e6) * (isNum(rt.cachedTextInputPer1MTokens) ? rt.cachedTextInputPer1MTokens : 0)
        + (rtTout / 1e6) * (isNum(rt.textOutputPer1MTokens) ? rt.textOutputPer1MTokens : 0);
    }
  }
  return { costUsdMicro: Math.round(usd * 1e6), priceMissing: missing };
}
