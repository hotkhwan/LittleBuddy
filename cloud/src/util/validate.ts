import { errors } from '../errors';

export const ID_RE = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
export const MAX_TRANSCRIPT = 500;
export const MAX_AUDIO_SECONDS = 30;

export interface StrOpts { required?: boolean; max?: number; re?: RegExp }

/** Bounded string field reader shared by every route. */
export function str(body: unknown, field: string, o: StrOpts = {}): string {
  const v = (body as Record<string, unknown> | null | undefined)?.[field];
  if (v === undefined || v === null || v === '') {
    if (o.required) throw errors.badRequest(`${field} is required`);
    return '';
  }
  if (typeof v !== 'string') throw errors.badRequest(`${field} must be a string`);
  if (o.max && v.length > o.max) throw errors.badRequest(`${field} is too long (max ${o.max})`);
  if (o.re && !o.re.test(v)) throw errors.badRequest(`${field} has an invalid format`);
  return v;
}

export function intField(body: unknown, field: string, o: { min?: number; max?: number; fallback?: number; required?: boolean } = {}): number {
  const v = (body as Record<string, unknown> | null | undefined)?.[field];
  if (v === undefined || v === null || v === '') {
    if (o.required) throw errors.badRequest(`${field} is required`);
    return o.fallback ?? 0;
  }
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n) || Math.floor(n) !== n) throw errors.badRequest(`${field} must be an integer`);
  if (o.min !== undefined && n < o.min) throw errors.badRequest(`${field} must be >= ${o.min}`);
  if (o.max !== undefined && n > o.max) throw errors.badRequest(`${field} must be <= ${o.max}`);
  return n;
}

export function boolField(body: unknown, field: string, fallback: boolean): boolean {
  const v = (body as Record<string, unknown> | null | undefined)?.[field];
  if (v === undefined || v === null) return fallback;
  if (typeof v !== 'boolean') throw errors.badRequest(`${field} must be true or false`);
  return v;
}

export function isObject(v: unknown): v is Record<string, unknown> {
  return Boolean(v) && typeof v === 'object' && !Array.isArray(v);
}
