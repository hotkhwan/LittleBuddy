// Minimal path router: exact segments and {param} placeholders. No regex DSL.

/**
 * @typedef {(ctx: import('./types.js').RequestContext) => Promise<import('./types.js').Response> | import('./types.js').Response} Handler
 */

export function createRouter() {
  /** @type {{method: string, pattern: string, parts: string[], handler: Handler}[]} */
  const routes = [];

  /**
   * @param {string} method
   * @param {string} pattern e.g. "/api/v1/tutor/sessions/{id}/turns"
   * @param {Handler} handler
   */
  function add(method, pattern, handler) {
    routes.push({ method: method.toUpperCase(), pattern, parts: split(pattern), handler });
  }

  /**
   * @param {string} method
   * @param {string} pathname
   * @returns {{handler: Handler, params: Record<string, string>, pattern: string} | {allowed: string[]} | null}
   */
  function match(method, pathname) {
    const parts = split(pathname);
    const allowed = [];
    for (const route of routes) {
      const params = matchParts(route.parts, parts);
      if (!params) continue;
      if (route.method === method.toUpperCase()) return { handler: route.handler, params, pattern: route.pattern };
      allowed.push(route.method);
    }
    return allowed.length ? { allowed } : null;
  }

  return { add, match };
}

/** @param {string} p */
function split(p) {
  return p.split('/').filter(Boolean).map(decodeSafe);
}

/** @param {string} s */
function decodeSafe(s) {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

/**
 * @param {string[]} pattern
 * @param {string[]} actual
 */
function matchParts(pattern, actual) {
  if (pattern.length !== actual.length) return null;
  /** @type {Record<string, string>} */
  const params = {};
  for (let i = 0; i < pattern.length; i += 1) {
    const p = pattern[i];
    if (p.startsWith('{') && p.endsWith('}')) {
      params[p.slice(1, -1)] = actual[i];
    } else if (p !== actual[i]) {
      return null;
    }
  }
  return params;
}
