# Family Club

**Status: a provider-neutral entitlement interface. THERE IS NO BILLING IN THIS BUILD.**

Nothing in this repository can take money. There is no payment SDK, no StoreKit, no Play
Billing, no payment credentials, no product id, no receipt, no paywall and no purchase call
of any kind. The prices below are **PROPOSED, NOT FINAL**, and they exist in the product only
as words on a screen a grown-up has to hold a button for three seconds to reach.

`game/tests/cases/test_entitlement_no_purchase_guard.gd` fails the build if any of that
changes by accident.

---

## Pricing (PROPOSED — NOT FINAL)

| Tier | Price | Status |
| --- | --- | --- |
| Free Starter | free, forever, no account | **shipped** — this is what the build grants |
| Family Club | **USD 2.99 / month** | proposed, cannot be bought |
| Family Club (Thailand) | **THB 99 / month** | proposed, cannot be bought |
| Family Club (annual) | **does not exist** | **NOT DECIDED — do not invent a number** |

Thailand is priced separately because it is the launch market and USD 2.99 is not what this
should cost there.

There is deliberately **no annual price anywhere** — not in the code, not in the UI, not in
this document. A made-up annual number on a parent's screen is worse than no number at all,
and the no-purchase guard test asserts that none has appeared ("/ year", "per year",
"annually", "29.99" are all rejected in the Parent Corner copy).

---

## What Free Starter actually contains

Defined once, as data, in `game/content/packs/free_starter.json`, with a compiled-in fallback
copy in `game/scripts/entitlement/free_starter.gd`:

| Field | Contents |
| --- | --- |
| `missions` | `imHungry`, `snackTime` — both real, chained, star-rated missions |
| `rooms` | `bedroom`, `bathroom`, `kitchen`, `livingRoom` — the whole house |
| `characters` | `littleBuddy` (baby), `buddy` (toddler) |
| `outfits` | none — no outfit system ships yet, and the free tier does not promise one |
| `audio` | all ten bundled sound effects |
| `entitlementId` | `freeStarter` |

This is the real game, not a demo. `test_entitlement_free_starter.gd` asserts the two
missions are present **and that they exist in `missions.json`**, that all four rooms are
there, that every audio id is a sound the build actually ships, and that the JSON file and
the compiled-in fallback are the same promise.

---

## The interface

```
EntitlementService.is_active(entitlement_id) -> bool
```

That is the whole caller-facing API. One question, no prices, no products, no receipts, no
"restore purchases". A question this narrow is what makes the provider swappable.

| File | Role |
| --- | --- |
| `scripts/entitlement/entitlement_ids.gd` | the closed id set: `freeStarter`, `familyClub` |
| `scripts/entitlement/entitlement_provider.gd` | the interface: `provider_id()`, `is_active()`, `trusts_cached_state()` |
| `scripts/entitlement/local_entitlement_provider.gd` | the only provider that exists: offline, grants `freeStarter`, nothing else |
| `scripts/entitlement/entitlement_service.gd` | the façade callers use, plus persistence |
| `scripts/entitlement/free_starter.gd` | the free set, as data |

### Adding a real store later

One new file implementing the three provider methods, and one line at startup:

```gdscript
entitlements.set_provider(AppStoreEntitlementProvider.new())
```

No caller changes. A call site that only ever asked "is this active?" cannot care how the
answer was reached. A store provider that wants to honour a cached receipt while offline
returns `true` from `trusts_cached_state()`; the offline provider returns `false`.

### The two failure rules

* **Fail CLOSED.** Unknown id, junk in the save file, no provider, a state version from a
  later build, a cache written by a different provider — all of it is a NO.
* **Fail OPEN for Free Starter, deliberately.** Whatever else is broken, a four-year-old is
  never told that the game they played yesterday is gone. No provider can revoke it; the rule
  lives in the service, above every provider.

### Editing `user://profile.json` grants nothing

The entitlement cache is stored under `settings.entitlements` and is **tagged with the
provider that wrote it**. The offline provider reports `trusts_cached_state() == false`, so
adding `"familyClub"` to the save file by hand achieves exactly nothing. That is structural,
not obfuscation, and it is tested.

---

## Intentionally NOT implemented

* any payment SDK, payment credential or store integration (StoreKit, Play Billing, anything)
* a production paywall, an upsell screen, a "go premium" button, a price fetch, a product list
* purchase, restore-purchases, receipt validation, subscription status polling
* any remote content delivery — packs are local files inside the build (`docs/CONTENT_PACKS.md`)
* an annual price
* any child-facing mention of money, subscriptions, locked content or an outside service
* any gating of existing gameplay. The entitlement layer is wired into **nothing** in the
  gameplay path yet: it is read only by Parent Corner, for display. Wiring it up is a Lead
  decision, and the shipped game today is the free game.

## Rules that are not negotiable

1. The child is never asked to pay, never shown a price, and never shown a locked teaser.
2. Buddy is never sad, needy or disappointed about money. No countdown, no "unlock me".
3. Every purchase-adjacent surface lives in Parent Corner, behind the existing 3-second
   press-and-hold gate, which was not weakened to make room for any of this.
4. Free Starter is never taken away.
