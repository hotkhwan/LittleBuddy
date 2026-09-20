// HTTP entry point: node backend/src/server.js
// JSON in/out, CORS for the game, request size limit, 10 s handler timeout,
// AbortController cancellation propagated to the provider.
import http from 'node:http';
import { loadConfig } from './config.js';
import { createApp } from './app.js';
import { errors } from './errors.js';

/**
 * @param {{app: ReturnType<typeof createApp>, log?: (msg: string) => void}} opts
 */
export function createHttpServer({ app, log = () => {} }) {
  const { config } = app;

  const server = http.createServer((req, res) => {
    const started = Date.now();
    const ac = new AbortController();
    let responded = false;

    // CORS only for origins on the explicit allowlist (finding L2); the Godot
    // client needs none. Unknown origins get no CORS headers at all.
    const origin = typeof req.headers.origin === 'string' ? req.headers.origin : '';
    const corsHeaders = origin && config.corsOrigins.includes(origin)
      ? {
        'access-control-allow-origin': origin,
        'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
        'access-control-allow-headers': 'content-type, idempotency-key, x-parent-approval',
        'access-control-max-age': '600',
        vary: 'Origin',
      }
      : {};
    let route = req.method === 'OPTIONS' ? 'preflight' : 'unmatched';

    /** @param {number} status @param {unknown} body @param {Record<string,string>} [headers] */
    const send = (status, body, headers = {}) => {
      if (responded) return;
      responded = true;
      clearTimeout(timer);
      const payload = JSON.stringify(body);
      res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(payload), 'cache-control': 'no-store', ...corsHeaders, ...headers });
      res.end(payload);
      // Access log: method + route pattern + status + ms. Never the URL (it
      // carries clientId / session ids), never headers or bodies (finding M1).
      log(`${req.method} ${route} -> ${status} ${Date.now() - started}ms`);
    };

    const timer = setTimeout(() => {
      ac.abort(new Error('handler_timeout'));
      send(504, errors.timeout().toBody());
    }, config.handlerTimeoutMs);

    // `res` closing before we responded means the client went away (req 'close'
    // fires as soon as the body is consumed, so it is not a cancellation signal).
    res.on('close', () => {
      if (!responded) ac.abort(new Error('client_closed'));
    });

    if (req.method === 'OPTIONS') {
      send(204, '', {});
      return;
    }

    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
    const ip = clientIp(req, config.trustProxy);

    /** @type {Buffer[]} */
    const chunks = [];
    let size = 0;
    let tooLarge = false;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (tooLarge) return;
      if (size > config.maxBodyBytes) {
        tooLarge = true;
        chunks.length = 0;
        send(413, errors.payloadTooLarge().toBody(), { connection: 'close' });
        return;
      }
      chunks.push(chunk);
    });
    req.on('error', () => {
      if (!responded) send(400, errors.badRequest('Request stream failed.').toBody());
    });
    req.on('end', async () => {
      if (tooLarge) return;
      let body = null;
      if (chunks.length) {
        try {
          body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        } catch {
          send(400, errors.badRequest('Body must be valid JSON.').toBody());
          return;
        }
      }
      /** @type {Record<string, string>} */
      const headers = {};
      for (const [k, v] of Object.entries(req.headers)) if (typeof v === 'string') headers[k.toLowerCase()] = v;
      const result = await app.dispatch({ method: req.method ?? 'GET', url, params: {}, headers, body, ip, signal: ac.signal });
      route = result.route ?? route;
      send(result.status, result.body, result.headers);
    });
  });

  server.on('close', () => app.close());
  return server;
}

/**
 * Client address for rate limiting. X-Forwarded-For is honoured only when
 * TRUST_PROXY=1 (finding M5), and then the LAST hop (the one appended by our
 * own proxy) is used, so a client cannot spoof it by sending the header.
 * @param {import('node:http').IncomingMessage} req
 * @param {boolean} trustProxy
 */
export function clientIp(req, trustProxy) {
  if (trustProxy) {
    const xff = req.headers['x-forwarded-for'];
    const raw = Array.isArray(xff) ? xff.join(',') : xff;
    if (typeof raw === 'string' && raw.trim()) {
      const hops = raw.split(',').map((h) => h.trim()).filter(Boolean);
      if (hops.length) return hops[hops.length - 1];
    }
  }
  return req.socket.remoteAddress || 'unknown';
}

const isMain = process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (isMain) {
  const config = loadConfig(process.env);
  const log = (msg) => console.log(`[tutor-backend] ${msg}`);
  const app = createApp({ config, log });
  const server = createHttpServer({ app, log });
  const stopRetention = app.retention.start();
  server.on('close', stopRetention);
  server.listen(config.port, config.host, () => {
    log(`listening on http://${config.host}:${config.port}  devMode=${config.devMode} provider=${app.providerNote} dataDir=${config.dataDir} allowlist=${app.allowlist.source} lessons=${app.lessons.lessons.size} budgetUsd=${config.monthlyBudgetUsd} retentionDays=${config.retentionDays}`);
    if (app.lessons.lessons.size === 0) log(`WARNING: no lessons loaded from ${config.lessonsDir}; sessions will be refused outside DEV_MODE (set LESSONS_DIR).`);
    if (!config.devMode && !app.approval.configured) log('WARNING: PARENT_APPROVAL_SECRET is not set; no session can be approved outside DEV_MODE.');
  });
  const shutdown = () => {
    log('shutting down');
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1000).unref();
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
