// Parent portal configuration. ONE constant decides which server the portal
// may talk to. It must stay a loopback address: portal_lib.js refuses any
// other host, and public/_headers's Content-Security-Policy blocks it a second
// time in the browser. There is no production value to put here.
export const API_BASE_URL = "http://127.0.0.1:8787";

// The development sign-in provider documented in docs/ALIZ_TUTOR_API.md 1.2:
// POST /v1/parents {provider:"dev", subject} works only when the server runs
// with DEV_MODE=1 (cloud: `npm run dev`; prototype: `DEV_MODE=1 node backend/src/server.js`).
export const DEV_PROVIDER = "dev";
export const DEFAULT_SUBJECT = "parent-demo";
