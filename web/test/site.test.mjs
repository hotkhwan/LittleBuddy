// Static checks for the Little Days site. Run: cd web && npm test (Node 22).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { dirname, extname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const publicRoot = join(webRoot, "public");

async function walk(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await walk(full)));
    else out.push(full);
  }
  return out;
}

const files = await walk(publicRoot);
const htmlFiles = files.filter((f) => extname(f) === ".html");
const textFiles = files.filter((f) => [".html", ".css", ".js", ".mjs", ".txt"].includes(extname(f)));
const pages = Object.fromEntries(await Promise.all(htmlFiles.map(async (f) => [relative(publicRoot, f), await readFile(f, "utf8")])));
const publicPaths = new Set(files.map((f) => "/" + relative(publicRoot, f).split("\\").join("/")));

function resolves(target) {
  // Mirrors Workers assets html_handling = "auto-trailing-slash".
  const clean = target.replace(/\/+$/, "") || "/index.html";
  return publicPaths.has(clean) || publicPaths.has(`${clean}.html`) || publicPaths.has(`${clean === "/index.html" ? "" : clean}/index.html`) || (target === "/" && publicPaths.has("/index.html"));
}

function idsIn(html) {
  return new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
}

test("every page is a well-formed document: lang, viewport, title, one h1, alt on every img", () => {
  assert.ok(htmlFiles.length >= 5, "home, privacy, support, parents, 404");
  for (const [name, html] of Object.entries(pages)) {
    assert.match(html, /^<!DOCTYPE html>/i, `${name}: doctype`);
    assert.match(html, /<html lang="en">/, `${name}: lang`);
    assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/, `${name}: viewport`);
    assert.match(html, /<title>[^<]{3,}<\/title>/, `${name}: title`);
    assert.equal((html.match(/<h1[\s>]/g) || []).length, 1, `${name}: exactly one h1`);
    for (const img of html.matchAll(/<img\b[^>]*>/g)) assert.match(img[0], /\salt="[^"]*"/, `${name}: img without alt: ${img[0]}`);
    assert.match(html, /<main id="main"/, `${name}: main landmark`);
    assert.match(html, /class="skip-link"/, `${name}: skip link`);
  }
});

test("every internal link, script, stylesheet and image resolves to a file; every fragment exists", () => {
  for (const [name, html] of Object.entries(pages)) {
    const ids = idsIn(html);
    const refs = [...html.matchAll(/\s(?:href|src)="([^"]+)"/g)].map((m) => m[1]);
    for (const ref of refs) {
      if (/^(https?:|mailto:|tel:|data:)/.test(ref)) continue;
      if (ref.startsWith("#")) {
        assert.ok(ids.has(ref.slice(1)), `${name}: fragment ${ref} not found`);
        continue;
      }
      const [path, fragment] = ref.split("#");
      assert.ok(path.startsWith("/"), `${name}: use root-relative links (${ref})`);
      assert.ok(resolves(path), `${name}: broken link ${ref}`);
      if (fragment) {
        const targetName = path === "/" ? "index.html" : `${path.replace(/^\//, "").replace(/\/$/, "")}/index.html`;
        const target = pages[targetName] ?? pages[`${path.replace(/^\//, "")}.html`];
        assert.ok(target && idsIn(target).has(fragment), `${name}: fragment ${ref} not found in ${path}`);
      }
    }
  }
});

test("no external resources: nothing loads from a third party", () => {
  for (const [name, html] of Object.entries(pages)) {
    for (const m of html.matchAll(/\s(?:href|src)="(https?:\/\/[^"]+)"/g)) assert.fail(`${name}: external resource ${m[1]}`);
  }
  const css = pages["assets/site.css"] ?? "";
  assert.doesNotMatch(css, /@import|url\(\s*["']?https?:/, "site.css: no remote imports");
});

test("no TODO remains except the support contact block", async () => {
  for (const file of textFiles) {
    const text = await readFile(file, "utf8");
    const rel = relative(publicRoot, file);
    for (const [i, line] of text.split("\n").entries()) {
      if (!/TODO|FIXME|XXX/.test(line)) continue;
      assert.equal(rel, "support/index.html", `${rel}:${i + 1}: unexpected TODO: ${line.trim()}`);
      assert.match(line, /TODO\(owner\)/, `${rel}:${i + 1}: the support TODO must be marked for the owner`);
    }
  }
  const support = pages["support/index.html"];
  assert.match(support, /TODO\(owner\): replace this block with the real support contact/, "support keeps its owner placeholder");
  assert.doesNotMatch(support.replace(/<!--[\s\S]*?-->/g, ""), /mailto:/, "no invented mailto until the owner supplies an address");
});

test("no 'unlimited' or 'guaranteed' wording, and no invented pricing on public pages", async () => {
  for (const file of textFiles) {
    const rel = relative(publicRoot, file);
    const text = await readFile(file, "utf8");
    assert.doesNotMatch(text, /unlimited|guaranteed?/i, `${rel}: banned wording`);
  }
  for (const [name, html] of Object.entries(pages)) {
    assert.doesNotMatch(html, /THB\s*\d|\$\s?\d|USD\s*\d|per month/i, `${name}: no prices on public pages`);
  }
});

test("privacy page carries the exact tutor sentence and only the claims the code guarantees", () => {
  const privacy = pages["privacy/index.html"];
  assert.ok(privacy.includes("The online AI tutor is switched off in this build."), "exact sentence present");
  for (const phrase of ["fully offline", "No account", "No ads", "on-device recognition required", "never words", "docs/ALIZ_TUTOR_PRIVACY_REVIEW.md", "docs/GOOGLE_PLAY_RELEASE_READINESS.md"]) {
    assert.ok(privacy.includes(phrase), `privacy mentions: ${phrase}`);
  }
  // Every future-tense feature is labelled planned.
  const planned = privacy.slice(privacy.indexOf('id="planned"'), privacy.indexOf('id="website"'));
  assert.ok((planned.match(/pill ghost/g) || []).length >= 3, "each planned item is marked");
  assert.doesNotMatch(privacy, /we (never|do not) (sell|share) your data/i, "no marketing-style absolutes beyond what is verified");
});

test("home page positioning and honesty markers", () => {
  const home = pages["index.html"];
  assert.ok(home.includes("Aliz, your child's playful learning companion"));
  assert.match(home, /free game/i);
  assert.match(home, /switched off in the current build/);
  assert.match(home, /coming later/);
  assert.match(home, /lang="th"/, "Thai helper lines present");
});

test("Thai helper lines follow English on every public page", () => {
  for (const name of ["index.html", "privacy/index.html", "support/index.html", "parents/index.html"]) {
    const html = pages[name];
    const firstTh = html.indexOf('lang="th"');
    assert.ok(firstTh > 0, `${name}: has a Thai helper line`);
    const before = html.slice(html.indexOf("<body"), firstTh).replace(/<[^>]+>/g, " ");
    assert.match(before, /[A-Za-z]{3,}/, `${name}: English text comes before the first Thai helper`);
    assert.ok((html.match(/lang="th"/g) || []).length >= 3, `${name}: Thai helpers throughout, not just once`);
  }
});

test("wrangler.toml: static assets only, no routes, no custom domain, no workers.dev", async () => {
  const toml = await readFile(join(webRoot, "wrangler.toml"), "utf8");
  assert.match(toml, /^name = "littledays-web"$/m);
  assert.match(toml, /^account_id = "8d67bfb5b60f8e54544e4aac74a98cc9"$/m);
  assert.match(toml, /^workers_dev = false$/m);
  assert.match(toml, /^\[assets\]\s*\ndirectory = "\.\/public"/m);
  const active = toml.split("\n").filter((l) => !l.trim().startsWith("#")).join("\n");
  assert.doesNotMatch(active, /^\s*(routes?|route)\s*=|\[\[routes\]\]|custom_domain|pattern\s*=|zone_name|api\.littledays/m, "no routes or domains filled in");
  assert.doesNotMatch(active, /^\s*main\s*=/m, "no Worker script: assets only");
});

test("headers: CSP restricts connect-src to loopback and blocks framing", async () => {
  const headers = await readFile(join(publicRoot, "_headers"), "utf8");
  const csp = headers.split("\n").find((l) => l.includes("Content-Security-Policy"));
  assert.ok(csp, "CSP present");
  const connect = csp.match(/connect-src ([^;]+)/)[1].trim().split(/\s+/);
  for (const src of connect) assert.match(src, /^'self'$|^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/, `connect-src allows ${src}`);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.match(csp, /script-src 'self'/);
});

test("portal config defaults to the loopback development server and the guard refuses anything else", async () => {
  const config = await import(join(publicRoot, "parents", "config.js"));
  assert.equal(config.API_BASE_URL, "http://127.0.0.1:8787");
  assert.equal(config.DEV_PROVIDER, "dev");
  const lib = await import(join(publicRoot, "parents", "portal_lib.js"));
  assert.equal(lib.isLoopbackUrl(config.API_BASE_URL), true);
  assert.equal(lib.isLoopbackUrl("http://localhost:8787"), true);
  for (const bad of ["https://api.littledays.joinanny.com", "https://littledays.joinanny.com", "http://10.0.0.5:8787", "ftp://127.0.0.1", "nonsense", "http://127.0.0.1.evil.com"]) {
    assert.equal(lib.isLoopbackUrl(bad), false, `refuses ${bad}`);
  }
  const portal = await readFile(join(publicRoot, "parents", "portal.js"), "utf8");
  assert.doesNotMatch(portal, /joinanny|https:\/\//, "portal.js hard-codes no remote host");
  assert.doesNotMatch(portal, /innerHTML/, "portal.js builds DOM without innerHTML");
});

test("portal helpers: mock store mirrors the API shapes; minutes and subscription summaries", async () => {
  const lib = await import(join(publicRoot, "parents", "portal_lib.js"));
  const store = lib.createMockStore(Date.UTC(2026, 8, 21, 10, 0, 0));
  const signIn = await store.signIn("parent-demo");
  assert.ok(signIn.parentToken && signIn.parentId);
  const { children } = await store.children();
  assert.equal(children.length, 2);
  for (const c of children) for (const key of ["childId", "nickname", "avatarId", "birthYearBucket", "locale", "createdAt"]) assert.ok(key in c, `child has ${key}`);
  const consent = await store.consent();
  assert.deepEqual(Object.keys(consent.consent).sort(), ["ai_tutor", "privacy", "voice"]);
  assert.equal(consent.consent.ai_tutor.granted, false);
  const updated = await store.setConsent("ai_tutor", true);
  assert.equal(updated.consent.ai_tutor.granted, true);
  const quota = await store.quota(children[0].childId);
  assert.equal(quota.quota.dailyAllowanceSeconds, 300);
  assert.equal(quota.quota.resetAtUtc, "2026-09-22T00:00:00.000Z");
  const m = lib.minutesSummary(quota.quota);
  assert.deepEqual([m.used, m.allowance, m.percent], [3, 5, 43]);
  assert.equal(m.text, "3 of 5 minutes used today");
  const sub = lib.subscriptionSummary(await store.entitlements());
  assert.equal(sub.status, "not available");
  assert.match(sub.text, /not available yet/);
  assert.equal(lib.nicknameProblem("Nong Mai"), null);
  assert.match(lib.nicknameProblem("mail@example.com"), /letters, digits|contact details/);
  assert.match(lib.nicknameProblem(""), /nickname/);
  assert.equal(lib.initialFor("bo"), "B");
  const child = await store.addChild("Pim");
  assert.equal((await store.children()).children.length, 3);
  assert.equal((await store.quota(child.childId)).quota.usedSeconds, 0);
});
