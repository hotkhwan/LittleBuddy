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

    const corsHeaders = {
      'access-control-allow-origin': config.corsOrigin,
      'access-control-allow-methods': 'GET, POST, OPTIONS',
      'access-control-allow-headers': 'content-type, idempotency-key',
      'access-control-max-age': '600',
    };

    /** @param {number} status @param {unknown} body @param {Record<string,string>} [headers] */
    const send = (status, body, headers = {}) => {
      if (responded) return;
      responded = true;
      clearTimeout(timer);
      const payload = JSON.stringify(body);
      res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(payload), 'cache-control': 'no-store', ...corsHeaders, ...headers });
      res.end(payload);
      log(`${req.method} ${req.url} -> ${status} ${Date.now() - started}ms`);
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
    const ip = (typeof req.headers['x-forwarded-for'] === 'string' && config.devMode ? req.headers['x-forwarded-for'].split(',')[0].trim() : '') || req.socket.remoteAddress || 'unknown';

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
      send(result.status, result.body, result.headers);
    });
  });

  server.on('close', () => app.close());
  return server;
}

const isMain = process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (isMain) {
  const config = loadConfig(process.env);
  const log = (msg) => console.log(`[tutor-backend] ${msg}`);
  const app = createApp({ config, log });
  const server = createHttpServer({ app, log });
  server.listen(config.port, config.host, () => {
    log(`listening on http://${config.host}:${config.port}  devMode=${config.devMode} provider=${app.providerNote} dataDir=${config.dataDir} allowlist=${app.allowlist.source}`);
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
