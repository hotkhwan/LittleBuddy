// Shared test rig: the fixture chain as x5c, JWS signing with the fixture leaf,
// a fake fetch, a fixed clock, and a mock-transaction builder.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { base64Encode, pemToDer, sha256Hex } from '../crypto/encoding.ts';
import { importPkcs8, signJws } from '../crypto/jws.ts';
import type { NormalizedTransaction } from '../types.ts';

const FIXTURES = join(import.meta.dirname, 'fixtures');

export const NOW_MS = Date.UTC(2026, 8, 21, 12, 0, 0); // 2026-09-21T12:00:00Z
export const DAY_MS = 24 * 3600 * 1000;

export function pem(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf8');
}

export function x5cOf(...names: string[]): string[] {
  return names.map((n) => base64Encode(pemToDer(pem(n))));
}

export const CHAIN = x5cOf('leaf.pem', 'inter.pem', 'root.pem');
export const ROGUE_CHAIN = x5cOf('rogue_leaf.pem', 'rogue_root.pem');

export async function fixtureRootSha256(): Promise<string> {
  return sha256Hex(pemToDer(pem('root.pem')));
}

export async function signWithFixtureLeaf(payload: Record<string, unknown>, header: Record<string, unknown> = {}, keyName = 'leaf.pkcs8.pem', chain: string[] = CHAIN): Promise<string> {
  const key = await importPkcs8(pem(keyName), 'ES256');
  return signJws({ x5c: chain, ...header }, payload, key, 'ES256');
}

export interface FakeCall {
  url: string;
  init: RequestInit | undefined;
}

export function fakeFetch(routes: Array<{ match: (url: string, init?: RequestInit) => boolean; status: number; body: unknown }>): { fetch: typeof fetch; calls: FakeCall[] } {
  const calls: FakeCall[] = [];
  const impl = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    calls.push({ url, init });
    const route = routes.find((r) => r.match(url, init));
    if (!route) return new Response('not found', { status: 404 });
    return new Response(typeof route.body === 'string' ? route.body : JSON.stringify(route.body), { status: route.status, headers: { 'content-type': 'application/json' } });
  }) as typeof fetch;
  return { fetch: impl, calls };
}

export function clock(startMs = NOW_MS): { now: () => number; set: (ms: number) => void; advance: (ms: number) => void } {
  let current = startMs;
  return { now: () => current, set: (ms) => { current = ms; }, advance: (ms) => { current += ms; } };
}

export function tx(overrides: Partial<NormalizedTransaction> = {}): NormalizedTransaction {
  return {
    store: 'apple',
    productId: 'little_days_family_monthly',
    transactionId: 'tx-1',
    originalTransactionId: 'orig-1',
    purchaseTimeMs: NOW_MS - DAY_MS,
    expiresAtMs: NOW_MS + 29 * DAY_MS,
    revokedAtMs: null,
    gracePeriodExpiresAtMs: null,
    autoRenewing: true,
    environment: 'sandbox',
    accountToken: null,
    eventTimeMs: NOW_MS - DAY_MS,
    source: 'verify',
    ...overrides,
  };
}

export function appleTransactionPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    transactionId: '2000000123456789',
    originalTransactionId: '2000000100000000',
    bundleId: 'com.littledays.app',
    productId: 'little_days_family_monthly',
    purchaseDate: NOW_MS - DAY_MS,
    originalPurchaseDate: NOW_MS - DAY_MS,
    expiresDate: NOW_MS + 29 * DAY_MS,
    type: 'Auto-Renewable Subscription',
    environment: 'Sandbox',
    signedDate: NOW_MS - 3600_000,
    inAppOwnershipType: 'PURCHASED',
    ...overrides,
  };
}

export async function jsonOf(response: Response): Promise<Record<string, unknown>> {
  return (await response.json()) as Record<string, unknown>;
}

export function request(method: string, path: string, body?: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`https://worker.test${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

/** An RSA service-account key for the Google token path, minted per test run. */
export async function rsaPkcs8Pem(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const b64 = base64Encode(der).replace(/(.{64})/g, '$1\n');
  return `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;
}
