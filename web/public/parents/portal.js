// Parent portal shell. Two data sources with one interface:
//   - "mock": createMockStore() in portal_lib.js (sample data, in memory)
//   - "dev":  fetch against API_BASE_URL, which must be a loopback address
// Everything rendered here is development data; the banner says so.
import { API_BASE_URL, DEV_PROVIDER, DEFAULT_SUBJECT } from "./config.js";
import {
  CONSENT_KINDS, CONSENT_LABELS, SUBJECT_RE, createMockStore, initialFor,
  isLoopbackUrl, minutesSummary, nicknameProblem, subscriptionSummary,
} from "./portal_lib.js";

const $ = (id) => document.getElementById(id);
const SESSION_KEY = "littledays.portal.dev-session";
const AVATAR_TONES = ["pink", "mint", "blue", "lavender", "peach"];

let client = null;
let state = { children: [], consent: null };

// ---------------------------------------------------------------- dev client
function devClient(token) {
  const base = API_BASE_URL.replace(/\/+$/, "");
  const call = async (method, path, body) => {
    if (!isLoopbackUrl(base)) throw new Error(`Refusing to call ${base}: only a loopback development server is allowed.`);
    const headers = { accept: "application/json" };
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    let response;
    try {
      response = await fetch(`${base}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), mode: "cors", credentials: "omit" });
    } catch (error) {
      throw new Error(`Could not reach ${base}. Is the development server running with DEV_MODE=1, and does it allow this page's origin (CORS)? (${error.message})`);
    }
    const text = await response.text();
    let json = {};
    try { json = text ? JSON.parse(text) : {}; } catch { json = {}; }
    if (!response.ok) {
      const code = json?.error?.code ?? `http_${response.status}`;
      const message = json?.error?.message ?? response.statusText;
      throw new Error(`${code}: ${message}`);
    }
    return json;
  };
  return {
    kind: "dev",
    async signIn(subject) {
      const out = await call("POST", "/v1/parents", { provider: DEV_PROVIDER, subject });
      token = out.parentToken;
      return out;
    },
    me: () => call("GET", "/v1/parents/me"),
    children: () => call("GET", "/v1/children"),
    addChild: (nickname) => call("POST", "/v1/children", { nickname }),
    consent: () => call("GET", "/v1/consent"),
    setConsent: (kind, granted) => call("PUT", "/v1/consent", { kind, granted }),
    quota: (childId) => call("GET", `/v1/tutor/quota?childId=${encodeURIComponent(childId)}`),
    entitlements: () => call("GET", "/v1/entitlements"),
    get token() { return token; },
  };
}

// ------------------------------------------------------------------ helpers
function setStatus(id, text, isError = false) {
  const el = $(id);
  el.textContent = text;
  el.classList.toggle("error", Boolean(isError && text));
}

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k === "html") throw new Error("markup strings are not accepted here");
    else if (v === true) node.setAttribute(k, "");
    else if (v !== false && v !== null && v !== undefined) node.setAttribute(k, String(v));
  }
  for (const child of children) node.append(child);
  return node;
}

function saveSession(session) {
  try { sessionStorage.setItem(SESSION_KEY, JSON.stringify(session)); } catch { /* private mode: fine */ }
}
function loadSession() {
  try { return JSON.parse(sessionStorage.getItem(SESSION_KEY) || "null"); } catch { return null; }
}
function clearSession() {
  try { sessionStorage.removeItem(SESSION_KEY); } catch { /* ignore */ }
}

// ---------------------------------------------------------------- rendering
function renderChildren() {
  const list = $("child-list");
  list.replaceChildren();
  $("children-empty").hidden = state.children.length > 0;
  state.children.forEach((child, i) => {
    const tone = AVATAR_TONES[i % AVATAR_TONES.length];
    const details = [child.birthYearBucket ? `born ${child.birthYearBucket}` : null, child.locale || null].filter(Boolean).join(" · ");
    list.append(el("li", {}, [
      el("span", { class: `avatar ${tone}`, "aria-hidden": "true", text: initialFor(child.nickname) }),
      el("span", {}, [
        el("strong", { text: child.nickname }),
        document.createElement("br"),
        el("span", { class: "hint", text: details || "nickname only" }),
      ]),
    ]));
  });
}

function renderConsent() {
  const box = $("consent-list");
  box.replaceChildren();
  const consent = state.consent?.consent ?? {};
  for (const kind of CONSENT_KINDS) {
    const entry = consent[kind] ?? { granted: false };
    const inputId = `consent-${kind}`;
    const input = el("input", { type: "checkbox", id: inputId, role: "switch", "aria-checked": String(Boolean(entry.granted)), "data-kind": kind });
    input.checked = Boolean(entry.granted);
    input.addEventListener("change", onConsentChange);
    box.append(el("div", { class: "switch-row" }, [
      el("label", { class: "label", for: inputId }, [
        el("span", { text: CONSENT_LABELS[kind].en }),
        el("span", { class: "th", lang: "th", text: CONSENT_LABELS[kind].th }),
      ]),
      el("span", { class: "switch" }, [input, el("span", { class: "track", "aria-hidden": "true" })]),
    ]));
  }
}

async function renderMinutes() {
  const box = $("minutes-list");
  box.replaceChildren();
  if (!state.children.length) {
    box.append(el("p", { class: "hint", text: "Add a child profile to see today's minutes." }));
    return;
  }
  for (const child of state.children) {
    const row = el("div", {}, [el("strong", { text: child.nickname }), el("p", { class: "hint", text: "loading..." })]);
    box.append(row);
    try {
      const reply = await client.quota(child.childId);
      const m = minutesSummary(reply.quota);
      const reset = reply.quota?.resetAtUtc ? new Date(reply.quota.resetAtUtc) : null;
      // CSSOM, not a style attribute: the site's CSP has no 'unsafe-inline'.
      const fill = el("span");
      fill.style.width = `${m.percent}%`;
      row.replaceChildren(
        el("strong", { text: child.nickname }),
        el("div", { class: "meter", role: "img", "aria-label": `${child.nickname}: ${m.text}` }, [fill]),
        el("p", { class: "hint", text: `${m.text}${reset ? ` · resets ${reset.toLocaleString()}` : ""} · plan: ${reply.entitlement ?? "free"}` }),
      );
    } catch (error) {
      row.replaceChildren(el("strong", { text: child.nickname }), el("p", { class: "hint", text: `Minutes unavailable: ${error.message}` }));
    }
  }
}

async function renderSubscription() {
  try {
    const ent = await client.entitlements();
    const s = subscriptionSummary(ent);
    $("subscription-status").textContent = s.status;
    $("subscription-line").textContent = s.text;
  } catch (error) {
    $("subscription-status").textContent = "not available";
    $("subscription-line").textContent = `Subscriptions are not available yet. (${error.message})`;
  }
}

async function refreshAll() {
  const [children, consent] = await Promise.all([client.children(), client.consent()]);
  state.children = children.children ?? [];
  state.consent = consent;
  renderChildren();
  renderConsent();
  await Promise.all([renderMinutes(), renderSubscription()]);
}

// ------------------------------------------------------------------ events
async function onConsentChange(event) {
  const input = event.currentTarget;
  const kind = input.dataset.kind;
  const granted = input.checked;
  input.disabled = true;
  setStatus("consent-status", "Saving...");
  try {
    state.consent = await client.setConsent(kind, granted);
    input.setAttribute("aria-checked", String(granted));
    setStatus("consent-status", granted ? "Saved. Great!" : "Saved. Permission withdrawn.");
  } catch (error) {
    input.checked = !granted;
    input.setAttribute("aria-checked", String(!granted));
    setStatus("consent-status", `Could not save: ${error.message}`, true);
  } finally {
    input.disabled = false;
  }
}

async function onAddChild(event) {
  event.preventDefault();
  const field = $("nickname");
  const nickname = field.value.trim();
  const problem = nicknameProblem(nickname);
  if (problem) {
    setStatus("children-status", problem, true);
    field.focus();
    return;
  }
  setStatus("children-status", "Adding...");
  try {
    await client.addChild(nickname);
    field.value = "";
    setStatus("children-status", `Added ${nickname}. Nice!`);
    await refreshAll();
  } catch (error) {
    setStatus("children-status", `Could not add: ${error.message}`, true);
  }
}

async function onSignIn(event) {
  event.preventDefault();
  const source = new FormData($("signin-form")).get("source");
  const subject = $("subject").value.trim();
  if (!SUBJECT_RE.test(subject)) {
    setStatus("signin-status", "Please use letters, digits and _ . : - only.", true);
    $("subject").focus();
    return;
  }
  $("signin-button").disabled = true;
  setStatus("signin-status", source === "dev" ? `Signing in at ${API_BASE_URL}...` : "Loading sample data...");
  try {
    client = source === "dev" ? devClient(null) : createMockStore();
    const out = await client.signIn(subject);
    saveSession({ source, subject, token: source === "dev" ? out.parentToken : null });
    await showPortal(source, subject, out.parentId);
    setStatus("signin-status", "");
  } catch (error) {
    client = null;
    setStatus("signin-status", error.message, true);
  } finally {
    $("signin-button").disabled = false;
  }
}

async function showPortal(source, subject, parentId) {
  $("session-line").textContent = source === "dev"
    ? `Signed in as ${subject} (dev provider) at ${API_BASE_URL}. Parent id ${parentId}.`
    : `Sample data for ${subject}. Nothing is sent anywhere.`;
  $("portal").hidden = false;
  $("signin-section").hidden = true;
  await refreshAll();
  $("portal-title").focus?.();
}

function onSignOut() {
  clearSession();
  client = null;
  state = { children: [], consent: null };
  $("portal").hidden = true;
  $("signin-section").hidden = false;
  setStatus("signin-status", "Signed out.");
  $("subject").focus();
}

// -------------------------------------------------------------------- boot
async function boot() {
  $("api-base").textContent = API_BASE_URL;
  $("subject").value = DEFAULT_SUBJECT;
  if (!isLoopbackUrl(API_BASE_URL)) {
    const dev = document.querySelector('input[name="source"][value="dev"]');
    dev.disabled = true;
    $("source-hint").textContent = `The configured API base URL (${API_BASE_URL}) is not a loopback address, so the live option is disabled. Only sample data is available.`;
  }
  $("signin-form").addEventListener("submit", onSignIn);
  $("add-child-form").addEventListener("submit", onAddChild);
  $("signout-button").addEventListener("click", onSignOut);

  const session = loadSession();
  if (session?.source === "dev" && session.token && isLoopbackUrl(API_BASE_URL)) {
    client = devClient(session.token);
    try {
      const me = await client.me();
      await showPortal("dev", session.subject, me.parentId);
    } catch {
      clearSession();
      client = null;
    }
  }
}

boot();
