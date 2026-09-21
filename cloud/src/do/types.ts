import type { WireError } from '../errors';

/** RPC results carry errors as data: custom Error fields do not survive the DO boundary. */
export type DoResult<T> = { ok: true; value: T } | { ok: false; error: WireError };

export function ok<T>(value: T): DoResult<T> {
  return { ok: true, value };
}
