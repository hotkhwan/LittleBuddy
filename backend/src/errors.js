// API errors: every error leaving the server is {error:{code,message,...}}.
// Codes the game maps: quota_exhausted, not_approved, provider_unavailable,
// rate_limited, invalid_turn. Everything else is generic.

export class ApiError extends Error {
  /**
   * @param {number} status
   * @param {string} code
   * @param {string} message
   * @param {Record<string, unknown>} [extra]
   */
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }

  toBody() {
    return { error: { code: this.code, message: this.message, ...this.extra } };
  }
}

export const errors = {
  badRequest: (message = 'Bad request.', extra) => new ApiError(400, 'bad_request', message, extra),
  invalidTurn: (message = 'The turn request is not valid.', extra) => new ApiError(400, 'invalid_turn', message, extra),
  notApproved: (message = 'A parent needs to approve tutor time first.') => new ApiError(403, 'not_approved', message),
  unknownLesson: () => new ApiError(400, 'unknown_lesson', 'That lesson is not available.'),
  notFound: (message = 'Not found.') => new ApiError(404, 'not_found', message),
  sessionEnded: () => new ApiError(409, 'session_ended', 'This lesson session has already ended.'),
  idempotencyMismatch: () => new ApiError(422, 'idempotency_mismatch', 'Idempotency-Key was reused with a different request.'),
  payloadTooLarge: () => new ApiError(413, 'payload_too_large', 'Request body is too large.'),
  quotaExhausted: (quota, reason = 'daily_quota') => new ApiError(
    429,
    'quota_exhausted',
    reason === 'monthly_budget'
      ? 'Aliz is taking a rest today. Come back tomorrow for more Little Days!'
      : reason === 'daily_turns'
        ? 'Aliz needs a little rest. Come back tomorrow for more Little Days!'
        : 'Great job today! Come back tomorrow for more Little Days!',
    { reason, quota },
  ),
  rateLimited: (retryAfterSeconds) => new ApiError(429, 'rate_limited', 'Too many requests. Please wait a moment.', { retryAfterSeconds }),
  providerUnavailable: (message = 'The tutor is not available right now.') => new ApiError(503, 'provider_unavailable', message),
  timeout: () => new ApiError(504, 'timeout', 'The tutor took too long to answer.'),
  notImplemented: (message = 'Not implemented.') => new ApiError(501, 'not_implemented', message),
  internal: () => new ApiError(500, 'internal', 'Something went wrong.'),
};
