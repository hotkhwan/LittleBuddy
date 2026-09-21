// Local preview server: serves ./public the way Cloudflare Workers static
// assets will (directory index, /privacy -> /privacy/index.html, /404.html on
// a miss) and applies public/_headers. No dependencies; never used in production.
//   node tools/serve.mjs [port]      default 8788
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("../public/", import.meta.url)));
const port = Number(process.argv[2] || process.env.PORT || 8788);

const types = { ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".png": "image/png", ".svg": "image/svg+xml", ".json": "application/json; charset=utf-8", ".txt": "text/plain; charset=utf-8", ".ico": "image/x-icon" };

async function loadHeaders() {
  try {
    const text = await readFile(join(root, "_headers"), "utf8");
    const out = [];
    for (const raw of text.split("\n")) {
      const line = raw.replace(/#.*$/, "").trimEnd();
      if (!line.trim()) continue;
      if (!/^\s/.test(line)) out.push({ pattern: line.trim(), headers: {} });
      else if (out.length) {
        const [name, ...rest] = line.trim().split(":");
        out[out.length - 1].headers[name.trim()] = rest.join(":").trim();
      }
    }
    return out;
  } catch {
    return [];
  }
}

async function fileFor(pathname) {
  const clean = normalize(decodeURIComponent(pathname)).replace(/^(\.\.[/\\])+/, "");
  const candidates = clean.endsWith("/")
    ? [join(root, clean, "index.html")]
    : [join(root, clean), join(root, `${clean}.html`), join(root, clean, "index.html")];
  for (const file of candidates) {
    if (!file.startsWith(root)) continue;
    try {
      const s = await stat(file);
      if (s.isFile()) return { file, status: 200 };
    } catch { /* next */ }
  }
  return { file: join(root, "404.html"), status: 404 };
}

const rules = await loadHeaders();
const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const { file, status } = await fileFor(url.pathname);
  for (const rule of rules) if (rule.pattern === "/*" || rule.pattern === url.pathname) for (const [k, v] of Object.entries(rule.headers)) res.setHeader(k, v);
  try {
    const body = await readFile(file);
    res.writeHead(status, { "content-type": types[extname(file)] || "application/octet-stream", "content-length": body.length });
    res.end(body);
  } catch {
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  }
});
server.listen(port, "127.0.0.1", () => console.log(`Little Days site preview: http://127.0.0.1:${port}/  (root ${root})`));
