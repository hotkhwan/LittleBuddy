// Every error leaving the Worker is {error:{code,message,...}}. The codes are
// the prototype's (backend/src/errors.js) so game/scripts/tutor/quota/
// backend_response.gd maps them unchanged, plus three the account layer
// needs: consent_required (403, the game treats any 403 as "back to the
// parent gate"), conflict (409) and method_not_allowed (405).

export interface ErrorBody {
  error: { code: string; message: string } & Record<string, unknown>;
}

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly extra: Record<string, unknown>;

  constructor(status: number, code: string, message: string, extra: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }

  toBody(): ErrorBody {
    return { error: { code: this.code, message: this.message, ...this.extra } };
  }

  /** Plain data for crossing a Durable Object RPC boundary (custom fields do not survive `throw`). */
  toWire(): WireError {
    return { status: this.status, code: this.code, message: this.message, extra: this.extra };
  }

  static fromWire(w: WireError): ApiError {
    return new ApiError(w.status, w.code, w.message, w.extra ?? {});
  }
}

export interface WireError {
  status: number;
  code: string;
  message: string;
  extra?: Record<string, unknown>;
}

export type QuotaReason = 'daily_quota' | 'daily_turns' | 'monthly_budget';

export const errors = {
  badRequest: (message = 'Bad request.', extra?: Record<string, unknown>) => new ApiError(400, 'bad_request', message, extra),
  invalidTurn: (message = 'The turn request is not valid.', extra?: Record<string, unknown>) => new ApiError(400, 'invalid_turn', message, extra),
  notApproved: (message = 'A parent needs to approve tutor time first.') => new ApiError(403, 'not_approved', message),
  consentRequired: (kind: string) => new ApiError(403, 'consent_required', 'A parent needs to give consent in Parent Corner first.', { kind }),
  unknownLesson: () => new ApiError(400, 'unknown_lesson', 'That lesson is not available.'),
  notFound: (message = 'Not found.') => new ApiError(404, 'not_found', message),
  methodNotAllowed: (allowed: string[]) => new ApiError(405, 'method_not_allowed', `Use ${allowed.join(', ')}`, { allowed }),
  conflict: (message = 'Conflict.') => new ApiError(409, 'conflict', message),
  sessionEnded: () => new ApiError(409, 'session_ended', 'This lesson session has already ended.'),
  idempotencyMismatch: () => new ApiError(422, 'idempotency_mismatch', 'Idempotency-Key was reused with a different request.'),
  payloadTooLarge: () => new ApiError(413, 'payload_too_large', 'Request body is too large.'),
  quotaExhausted: (quota: unknown, reason: QuotaReason = 'daily_quota') => new ApiError(
    429,
    'quota_exhausted',
    reason === 'monthly_budget'
      ? 'Aliz is taking a rest today. Come back tomorrow for more Little Days!'
      : reason === 'daily_turns'
        ? 'Aliz needs a little rest. Come back tomorrow for more Little Days!'
        : 'Great job today! Come back tomorrow for more Little Days!',
    { reason, quota },
  ),
  rateLimited: (retryAfterSeconds: number) => new ApiError(429, 'rate_limited', 'Too many requests. Please wait a moment.', { retryAfterSeconds }),
  providerUnavailable: (message = 'The tutor is not available right now.') => new ApiError(503, 'provider_unavailable', message),
  timeout: () => new ApiError(504, 'timeout', 'The tutor took too long to answer.'),
  notImplemented: (message = 'Not implemented.') => new ApiError(501, 'not_implemented', message),
  internal: () => new ApiError(500, 'internal', 'Something went wrong.'),
};
