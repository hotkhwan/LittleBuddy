// THE ONE CONFIG FILE for Family Club billing. Product ids, what they grant,
// the daily tutor allowances, the grace/cache windows, and the PROPOSED price
// (labelled proposed; the app never invents a number and nothing here charges).
//
// The Godot client mirrors the product ids in
// game/scripts/entitlement/store/store_products.gd and the allowances in
// game/content/tutor/quota_config.json. If either changes, change it here too.

export const ENTITLEMENT_FAMILY_CLUB = 'familyClub' as const;
export type EntitlementId = typeof ENTITLEMENT_FAMILY_CLUB;

/** Quota-layer names (backend/src/quota.js, game quota_config.gd). */
export type QuotaTier = 'free' | 'family_club';

export const PRODUCT_FAMILY_MONTHLY = 'little_days_family_monthly';
export const PRODUCT_FAMILY_YEARLY = 'little_days_family_yearly';

export type ProductId = typeof PRODUCT_FAMILY_MONTHLY | typeof PRODUCT_FAMILY_YEARLY;

export interface ProductDefinition {
  readonly productId: ProductId;
  readonly entitlementId: EntitlementId;
  /** Nominal period, used only for the mock store and for sanity bounds. */
  readonly nominalPeriodDays: number;
}

export const PRODUCTS: ReadonlyArray<ProductDefinition> = Object.freeze([
  Object.freeze({ productId: PRODUCT_FAMILY_MONTHLY, entitlementId: ENTITLEMENT_FAMILY_CLUB, nominalPeriodDays: 30 }),
  Object.freeze({ productId: PRODUCT_FAMILY_YEARLY, entitlementId: ENTITLEMENT_FAMILY_CLUB, nominalPeriodDays: 365 }),
]);

export function productById(productId: unknown): ProductDefinition | null {
  if (typeof productId !== 'string') return null;
  return PRODUCTS.find((p) => p.productId === productId) ?? null;
}

export function isKnownProduct(productId: unknown): productId is ProductId {
  return productById(productId) !== null;
}

/** Daily active-tutor allowance in seconds, per UTC day. Never unlimited. */
export const DAILY_ALLOWANCE_SECONDS: Readonly<Record<QuotaTier, number>> = Object.freeze({
  free: 300,
  family_club: 1800,
});

export const BILLING_CONFIG = Object.freeze({
  /**
   * How long after an Apple/Google subscription lapses a family keeps access
   * while the store retries payment, when the store did not give an explicit
   * grace end. Apple: Billing Grace Period (if enabled in App Store Connect,
   * signedRenewalInfo.gracePeriodExpiresDate is authoritative). Google: state
   * IN_GRACE_PERIOD carries the extended expiryTime. This fallback is short.
   */
  fallbackGraceSeconds: 3 * 24 * 3600,
  /** The client may believe a decision offline for this long (mirrors BillingFlags). */
  clientOfflineCacheSeconds: 72 * 3600,
  /** How many devices (subjects) may attach to one subscription via verify/restore. */
  maxSubjectsPerSubscription: 6,
  /** Reject a store payload whose event time is this far in the future (clock skew). */
  maxFutureSkewMs: 5 * 60 * 1000,
  /** A store expiry further out than this is not a subscription we sell. */
  maxPeriodDays: 400,
  /** App Store Server API hosts (used only by the injected fetch). */
  appleApiBase: {
    production: 'https://api.storekit.itunes.apple.com',
    sandbox: 'https://api.storekit-sandbox.itunes.apple.com',
  },
  /**
   * SHA-256 of the DER-encoded "Apple Root CA - G3". Pinned so a JWS chain
   * that ends anywhere else is rejected. VERIFY AT ACTIVATION against
   * https://www.apple.com/certificateauthority/ and override with the
   * APPLE_ROOT_CA_G3_SHA256 env var if it differs.
   */
  appleRootCaG3Sha256Hex: '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179',
  /** Apple's OIDs that must be present on the leaf / intermediate of a signed payload. */
  appleLeafOid: '1.2.840.113635.100.6.11.1',
  appleIntermediateOid: '1.2.840.113635.100.6.2.1',
  googleApiBase: 'https://androidpublisher.googleapis.com/androidpublisher/v3',
  googleScope: 'https://www.googleapis.com/auth/androidpublisher',
});

/**
 * PRICE HYPOTHESIS. Information only, labelled proposed. The store's own
 * localized price is what a customer would ever see on a purchase sheet; this
 * number configures nothing and charges nobody.
 */
export const PRICING_PROPOSED = Object.freeze({
  currency: 'THB',
  monthly: 99,
  yearly: null as number | null, // NOT DECIDED -- do not invent a number
  status: 'proposed' as const,
});
