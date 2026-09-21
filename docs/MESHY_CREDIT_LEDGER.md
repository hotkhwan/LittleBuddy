# Meshy Credit Ledger

## Visual Production V3 — 2026-09-21

- Authentication verified with the existing Keychain-backed balance tool, HTTP 200.
- Balance before: **3144** credits, reverified at 16:05:45 UTC.
- Owner subsequently explicitly authorised justified V3 Meshy replacements,
  without a fixed cap. This authorisation supersedes the historical per-operation
  approval rule below for this sprint. Existing accepted characters and props
  remain excluded from regeneration.
- Proposed batch: **one baby bottle, 15 credits estimated** (Smart Topology
  preview 5, refine 10 only after preview review). No other generation proposed.
- Existing accepted fruit, teddy, toy box, table/chairs and number-block GLBs
  are retained. Their import/triangle checks remain part of the suite.
- Bottle: the current plain stacked primitives remain weak beside accepted
  textured fruit and toy props. Generate one rounded toy bottle with a readable
  collar/teat; both empty-bottle and milk routes reuse it with a preserved fill
  distinction. Selection cards render the actual integrated object.
- Refrigerator and wardrobe: no confirmed model defect requiring replacement;
  composition and UI receive the work.
- Final balance is recorded in `docs/VISUAL_PRODUCTION_V3.md` after validation.

Every credit-consuming Meshy operation is recorded here **before** it is run, and updated after.
No generation task may be created that does not appear in this table.

**Running total spent: 20 credits.** Overnight WOW pass used **10 of its 30-credit ceiling**; 20 credits remain unspent. Balance 3079 -> **3054**, verified before and after every operation. (Overnight WOW pass: owner set a **30-credit total ceiling** on 2026-09-19 with autonomous authority inside it. Overnight spend so far: see rows 3+.) (Balance 3079 → **3069**, verified before and
after every operation; each delta matches the task's `consumed_credits` exactly.)

Standing rules (owner-set):
- One approval covers **one operation**. Approving Remesh does not approve Rigging; approving
  Rigging does not approve Animation; a retry needs a new approval.
- Silence is not approval. Only an explicit "approved" / "approve" / "ok generate" / "ตกลง" /
  "อนุมัติ" counts.
- Zero-credit work (local inspection, prompt drafting, integration, tests, renders, docs, and
  reading the free animation library) needs no approval.

| # | Date | Asset | Operation | Endpoint | Est. credits | Actual | Outcome | Accepted? | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1a | 2026-09-18 | Baby standing (`baby_standing_v01`) | Remesh via `input_task_id` | `POST /openapi/v1/remesh` | ceiling 10 | **0** | **REJECTED — HTTP 400 `Invalid task mode texture`** | n/a | No task created, nothing charged. Not retried. See "Attempt 1" below. |
| 1b | 2026-09-18 | Baby standing (`baby_standing_v01`) | Remesh via `model_url`, `target_polycount 8000`, `topology quad`, `glb` | `POST /openapi/v1/remesh` | ceiling **10** | **5** | **SUCCEEDED** | **Yes — accepted** | Owner approved the `model_url` amendment. Remesh task `01a0b49b-48a0-775f-8b1f-6390a68681eb`, 85s. Result: 7,203 quads / 14,406 tris / 7,205 welded verts, watertight genus-0 all-quad. Saved to `game/assets_source/meshy/littleBuddy/babyStanding_remesh_v01.glb`. **Not integrated into any production scene.** Balance 3079 → 3074. |
| 2 | 2026-09-19 | Baby standing (`babyStanding_remesh_v01`) | Rigging via `input_task_id` | `POST /openapi/v1/rigging` | 5 (ceiling **5**) | **5** | **SUCCEEDED** | **Yes — accepted with one required fix** | Rig task `01a0b58b-4ca4-7663-80e9-97a4001a6f71`, 33s. 24-bone humanoid + free walk/run clips. Godot import, socket resolution, playback, iOS export and **arm64 build all pass**. One defect: leg weight bleed peaking 0.487 at the knees — fixable in Blender, no credits. Full report: `MESHY_RIG_VALIDATION.md`. **Not integrated into production.** Balance 3074 → 3069. |

## Known costs, from the API docs

| Operation | Cost |
|---|---|
| Remesh | **not published** — the response carries `consumed_credits`, so the true figure is only knowable after the first run |
| Rigging | **5 credits**, and **includes Walking + Running clips** |
| Animation, per action | **3 credits** (1–10 actions per request, 3 each) |
| Animation library listing | **free** |

The unpublished remesh cost is the reason operation #1 carries a **maximum authorised** figure
rather than an estimate — see the approval request.

## Why operation #1 is still blocked (2026-09-18)

**Correction.** An earlier revision of this section claimed the assets "were not created through
the API" and had no discoverable id. That was wrong, and it was inferred from a single weak
signal (empty listings). Direct retrieval proves tasks **do** exist for this key:
`GET /openapi/v2/text-to-3d/<id>` returns them. Only the *listing* endpoints come back empty,
under every parameter combination tried. So the id must be supplied by the owner, but a supplied
id **can** be verified here for free.

Two ways forward:

1. **Owner supplies the task id** from the Meshy web studio URL for the standing baby. Validate it
   first with `tools/meshy_validate_task.sh <id>` (zero credits), then `tools/meshy_remesh.sh <id>`.
2. **`model_url` instead of `input_task_id`** — rejected unless the owner asks for it: it requires
   publishing a paid asset to a publicly reachable URL.

Re-generating the baby to obtain an API-side task id is **not** an option under the current
approval (it is a new generation, and it would not reproduce the approved asset).

| 3 | 2026-09-19 | pinkGirl (`pinkGirl_v01`) | Remesh via `model_url`, `target_polycount 2000`, `topology quad`, `glb` | `POST /openapi/v1/remesh` | ~5 (overnight ceiling 30) | **5** | **SUCCEEDED — 4,341 tris, 341 OVER the 4,000 gate** | superseded by row 4 | Source task `01a0b38f-5233-7173-bcdb-5f97f4bb6109`, identity confirmed by preview. **Why the spend is justified under the owner's four tests:** she is 619,890 triangles and 22 MB, so she is not shippable at all and is currently switched OFF, leaving the caregiver invisible; the brief names her as required in the menu, the arrival and one gameplay scene; no local tool can decimate her (Blender absent); and she is the established character, so this is art direction rather than a new look. `target_polycount 2000` is chosen to land ~4,000 triangles, INSIDE art bible section 10's main-character budget rather than over it. |

| 4 | 2026-09-19 | pinkGirl (`pinkGirl_v01`) | Remesh via `model_url`, `target_polycount 1750`, `topology quad`, `glb` | `POST /openapi/v1/remesh` | 5 | **5** | **SUCCEEDED — 3,900 tris, inside the 4,000 gate** | — | Row 3 asked for 2000 quads and Meshy returned 2,170 (4,341 triangles), 341 over `MAX_TRIANGLES = 4000`. The owner's brief says not to raise the geometry budget to accommodate an asset, and weakening `test_buddy_avatar.gd` to pass would be the same thing by another route, so the ASSET is fixed instead. 1750 quads targets ~3,800 triangles with headroom for the same ~8.5% overshoot. Overnight total after this: **10 of 30**. |

| 5 | 2026-09-19 | pinkGirl (`pinkGirl_remesh_v02`) | Rigging via `input_task_id` `01a0b5e9-6dae-7430-ac20-493219f3bfce` | `POST /openapi/v1/rigging` | 5 | **5** | **SUCCEEDED — rig task `01a0b5ec-b2e5-7213-bc25-6ebdb686fe27`** | — | `test_buddy_avatar.gd` gates `ENABLED` on the asset being in budget AND able to animate. The budget half now passes; the rig half does not, because she has no skeleton. The alternative was to relax that guard to allow a static avatar -- but the owner's brief says not to weaken tests to turn them green, and rigging gives a genuinely better result (idle pose plus free walk/run) for the same 5 credits. Overnight total after this: **15 of 30**. |

## Attempt 1 of operation #1 — REJECTED by the API, 0 credits (2026-09-18)

Owner confirmed, and the approved Remesh was run once against the verified standing-baby id:

```
POST /openapi/v1/remesh
{ "input_task_id": "01a0b3a1-ca47-72da-85fb-bac548ffdae3",
  "target_formats": ["glb"], "topology": "quad", "target_polycount": 8000 }
-> HTTP 400  {"message":"Invalid task mode texture"}
```

**No remesh task was created and no credits were consumed** (balance 3079 before and after). This
was a request rejected at validation, not a task that ran and failed — but it was NOT retried,
per the standing "no automatic retry" rule.

**Cause.** Meshy's docs list *Text to 3D Preview* as a valid `input_task_id`, and
`GET /openapi/v2/text-to-3d/<id>` reports `mode: preview` for this task. The remesh validator
nevertheless classifies it as mode `texture` and refuses it. The task carries full PBR
`texture_urls`, so the studio texturing stage appears to change how remesh sees it while the GET
still reports `preview`. This is an inconsistency inside Meshy, and re-sending the identical
request cannot fix it.

**The documented alternative is `model_url`**, which Remesh accepts in place of `input_task_id`.
Meshy already publishes this exact asset on its own CDN:
`.../tasks/01a0b3a1-.../output/model.glb`, signature valid to **2126-08-25**, and it returns
**HTTP 200 without any auth header** at **11,822,300 bytes — byte-identical in size to the local
`baby_standing_v01.glb`**, a further confirmation of identity.

Note this does *not* carry the privacy cost the earlier "model_url rejected" note assumed: nothing
new is published anywhere. The URL is one Meshy itself issued, and it would be handed straight
back to Meshy. No third party is involved. It is a capability URL, so it should still not be
pasted into a public issue tracker or committed to the repo.

**Switching to `model_url` changes an approved parameter, so it needs the owner's approval before
it is run.** Awaiting that decision.

## Verified task ids (2026-09-18, zero credits)

Recovered from the macOS download provenance xattr
(`com.apple.metadata:kMDItemWhereFroms`) on each downloaded GLB. The Meshy download URL is
`https://assets.meshy.ai/uploads/converted/<TASK_ID>/<filename_with_pose_stamp>.glb`, so the task
id and the pose-bearing filename arrive **in the same string** — the binding is evidence, not a
filename guess. Every id was then retrieved from the API (id echo verified) and its preview
inspected by eye.

| Asset | Task ID | created_at (UTC) | Status | Visual confirmation |
|---|---|---|---|---|
| **Baby standing** | `01a0b3a1-ca47-72da-85fb-bac548ffdae3` | 08:28:40Z | SUCCEEDED | **upright**, light-blue romper, hair curl, white booties |
| Baby seated | `01a0b3a2-38d2-73de-acd3-a74cd4f80f09` | 08:29:08Z | SUCCEEDED | **sitting**, blue romper + bib, hair curl |
| Baby sleeping | `01a0b3a4-41a4-7702-aad0-6371383c3c74` | 08:31:22Z | SUCCEEDED | **lying down**, white onesie w/ pastel stars, eyes closed |
| pinkGirl | `01a0b38f-5233-7173-bcdb-5f97f4bb6109` | 08:08:30Z | SUCCEEDED | older girl, pink hair, striped dress |

**The method self-validates.** The xattr mapping assigns `01a0b3a4…` to the *sleeping* baby, and
that same id had already been independently proved to be the sleeping baby from its prompt and
preview image before any xattr was read. A known-answer case coming out right is what makes the
other three trustworthy.

**Blue romper + hair curl does NOT identify the standing baby** — the seated baby has both. Only
the pose separates them, so identification must be visual.

Ids are UUIDv7, so they sort by creation time: `01a0b38f` (pinkGirl) < `01a0b3a1` (standing) <
`01a0b3a2` (seated) < `01a0b3a4` (sleeping). Consistent with the observed `created_at` order.

## The filename-stamp match key was unsound

`tools/meshy_find_task.sh` assumed the filename stamp equals the task `created_at` within ±120s.
The real `created_at` values show the stamp is the **download** time, which lags creation by a
variable amount:

| Asset | created_at | filename stamp | lag | inside ±120s? |
|---|---|---|---|---|
| Standing | 08:28:40Z | 08:30:52 | 132s | **no** |
| Seated | 08:29:08Z | 08:31:43 | 155s | **no** |
| Sleeping | 08:31:22Z | 08:32:18 | 56s | yes |
| pinkGirl | 08:08:30Z | 08:15:31 | 421s | **no** |

So the original tool would have **failed to find the standing baby even with working listings**,
and the "four independent stamps agreeing to the second" claim in its header was never true —
it was never tested against a real `created_at`. The xattr route supersedes it.

## Two API behaviours that can burn a credit on the wrong asset

Both were found during zero-credit validation on 2026-09-18 and are now guarded in
`tools/meshy_validate_task.sh`. Anyone extending the Meshy tooling must preserve these guards.

1. **HTTP 200 does not mean "your id was found."** Retrieving the all-zeros sentinel UUID
   `00000000-…-000000000000` returns **200 with a different, real task** — in our case
   `01a0b3a4-41a4-7702-aad0-6371383c3c74`, the **sleeping** baby. The validator therefore compares
   the **returned `id` against the requested `id`** and rejects a mismatch, and refuses the
   sentinel outright. Genuine unknown ids do 404 correctly, and malformed ids 400, so the endpoint
   is otherwise sound.
2. **A 200 proves the task exists, never that it is the *right character*.** The four assets share
   one prompt template and differ only in pose/outfit. Identify before spending:

   | Asset | Stamp | Tell |
   |---|---|---|
   | Standing | `0918083052` | **blue** onesie, hair curl, upright |
   | Seated | `0918083143` | seated pose |
   | Sleeping | `0918083218` | **white** onesie w/ pastel stars, lying down, eyes closed |
   | pinkGirl | `0918081531` | pink, older girl |

   `01a0b3a4…` was confirmed as *sleeping* from its prompt (`Pose: lying down neutral pose`,
   `simple white baby onesie`) and its preview image. Remeshing it would have spent the standing
   baby's authorised credits on the wrong model.


## Overnight WOW pass — final accounting (2026-09-19)

| | |
|---|---|
| Ceiling authorised | **30 credits, total** |
| Spent | **10** (rows 3, 4 and 5 — all pinkGirl) |
| Remaining | **20, unspent** |
| Balance | 3064 → 3059 → 3054 |

Nothing was spent on the baby: the existing 14,406-triangle rigged runtime was
already working, and re-cutting it to ~3k would have cost another remesh plus
another rig (10 credits) to improve something that was not blocking the visible
experience. The brief's own rule — spend only where a local solution is
*noticeably* insufficient — pointed at pinkGirl instead, who was 619,890
triangles, 22 MB, and switched off entirely.

**An overwrite that cost nothing only because Meshy still had the task.**
`meshy_rig.sh` had its output paths hardcoded to the baby. Rigging pinkGirl
silently overwrote `babyStanding_rigged_v01.glb` and both of its clips — three
files that had already been paid for, with no warning and no prompt. They were
restored by re-downloading from rig task `01a0b58b-…` (URLs live until
2026-09-21). The tool now requires an output stem and refuses to overwrite an
existing file. Had this been noticed a day later, those assets would have been
gone.

---

## Sprint: Founder Preview (2026-09-19 → 21)

| | |
|---|---|
| Authorised ceiling | **100 new credits** |
| Spent | **0** |
| Remaining | **100, unspent** |
| Balance change | none from us. Zero-credit `GET /openapi/v1/balance` reads on 2026-09-20: 3134 (morning), 3184 (afternoon) — the account was credited, nothing was spent. No paid endpoint was called; all Aliz work was local (`ALIZ_POLISH_PASS.md`). |

**Nothing was spent because nothing could be.** `MESHY_API_KEY` is not present in
the build environment, so no request of any kind was issued. This is a fact about
the shell, not a judgement about the work: the Aliz replacement was authorised
and is wanted.

What was done instead, at zero cost, so the spend is one command when the key
arrives:

* `docs/reference/aliz_reference_v1.png` — a clean standalone reference built
  from the shipping model, with the modelled grin painted out and the torn
  fringe closed.
* `docs/reference/aliz_reference_apose.png` — the same figure with both arms
  swung 38 degrees out about the shoulders. This exists because image-to-3D
  **copies the pose in the picture**: no prompt text spreads the arms of an
  arms-down reference, and arms-down is what made the auto-rigger guess wrong
  the first time.
* `tools/meshy_aliz_apose.sh` — balance before and after, a typed `YES` before
  any paid call, no retry on failure, refusal to overwrite an existing file, and
  refusal of the all-zeros sentinel UUID. Every one of those guards is a thing
  that has already gone wrong on this project.

To unblock: `export MESHY_API_KEY=...` then `tools/meshy_aliz_apose.sh preview`.

Expected spend for the full experiment, to be confirmed against the live price
list before committing: one image-to-3D preview, then rigging only if the
preview passes a look-at-it review. Well inside 100.

## Character expression pass — Agent E (2026-09-20, evening)

| | |
|---|---|
| Balance before | **3184** (`GET /openapi/v1/balance`, HTTP 200, read at the start of the pass) |
| Balance after | **3184** (same call, end of the pass) |
| Paid calls | **none** |
| Spent | **0** |

Nothing blocked on a regeneration, so the protocol never got past step (a).
Everything in the pass was local and is documented in `docs/ALIZ_FACE_PASS.md`
and `docs/BUNNY_EMOTION_PASS.md`: Aliz's warmer face, her four moods and the
blink are texture patches on the shipping 512² atlas (`tools/aliz_face_pass.py`);
her idle and hair sway are an authored clip and a `SkeletonModifier3D` on the
skeleton she already has; Bunny's three new moods, his blink and his stamp are
repaints and keyframes on the shipping rig. The Bunny neck seam that was to be
inspected turned out not to exist on the mesh (0 boundary edges, 0 split
normals, no dark texels on the front of the neck band), so there was nothing to
regenerate. Standing ceiling of 100 credits: untouched.

## Tutor teaching props — Agent M (2026-09-20, evening)

Owner approval: Meshy for classroom teaching assets, inside the standing
**100-credit sprint ceiling**. Per-asset hard stop: 40 credits.

**Live price list, read 2026-09-20 from `docs.meshy.ai/en/api/pricing`
(zero credits):**

| Operation | Cost |
|---|---|
| Text-to-3D preview, Smart Topology (`model_type: smart-topology`, `ai_model: meshy-t2`) | **5** |
| Text-to-3D preview, Meshy-6 / lowpoly | 20 |
| Text-to-3D preview, Meshy-7 / 7.1 | 20 (+5 for `geometry_resolution` 2k/4k) |
| Text-to-3D refine, `texture_resolution` 2k/4k | **10** |
| Text-to-3D refine, 8k | 15 |
| Remesh | 5 |
| Auto-rigging | 5 |

**Plan (proposed before any paid call).** Smart Topology is the cheapest tier
that yields a usable texture: **5 (preview) + 10 (refine) = 15 credits per
asset**, and it accepts `target_polycount` 100–15,000 directly, so the ~3,000
triangle prop budget is asked for at generation time rather than paid for
again as a remesh. Order, stopping when credits or value run out:

| # | Asset | propId | Est. |
|---|---|---|---|
| T1 | Round pastel teaching table with two small chairs, one model | `table_set` | 15 |
| T2 | Red apple + yellow banana, one model | `fruit_set` | 15 |
| T3 | Toy-style cat and dog, one model | `cat_dog` (split later if separable) | 15 |
| T4 | Number blocks 1-2-3, one model | `number_blocks` | 15 |

Worst case **60 of 100**. A preview whose thumbnail is not usable is NOT
refined (10 credits saved, 5 written off) and is recorded as rejected. No
retries. Balance at plan time: **3184** (`GET /openapi/v1/balance`, HTTP 200,
15:06:46Z). Tool: `tools/meshy_tutor_text3d.sh` (balance before/after, explicit
`--yes`, no retry, no overwrite, sentinel refused, id echo compared).

| # | Date | Asset | Operation | Endpoint | Est. | Actual | Balance before → after | Task id | Outcome |
|---|---|---|---|---|---|---|---|---|---|
| T1a | 2026-09-20 15:08:55Z | `table_set` | Text-to-3D **preview**, smart-topology `meshy-t2`, 2800 tris | `POST /openapi/v2/text-to-3d` | 5 | **5** | 3184 → 3179 | `01a0bf5c-ef29-7008-90d4-e7de13bda01f` | **SUCCEEDED** 19s, 2,853 tris, 1 primitive; thumbnail reviewed: round table, chunky legs, two chairs — usable, refine approved |
| T1b | 2026-09-20 15:09:47Z | `table_set` | Text-to-3D **refine**, 2k texture, no PBR, on T1a | `POST /openapi/v2/text-to-3d` | 10 | **10** | 3179 → 3169 | `01a0bf5d-ba03-7253-99d1-5e4fa89e71bd` | **SUCCEEDED** ~5 min; 2,853 tris, 1 material, JPEG 2048² base colour; thumbnail: mint top, wood legs, yellow + pink chairs — **accepted**. T1 total 15. |
| T2a | 2026-09-20 15:15:29Z | `fruit_set` | Text-to-3D **preview**, smart-topology `meshy-t2`, 2800 tris | `POST /openapi/v2/text-to-3d` | 5 | **5** | 3169 → 3164 | `01a0bf62-ee3f-76db-84c7-3ae636d45f97` | **SUCCEEDED** 11s, 3,038 tris (38 over the gate — fixed locally, no credits); thumbnail: apple with stem + leaf, banana in front — usable, refine approved |
| T2b | 2026-09-20 15:16:10Z | `fruit_set` | Text-to-3D **refine**, 2k texture, no PBR, on T2a | `POST /openapi/v2/text-to-3d` | 10 | **10** | 3164 → 3154 | `01a0bf63-9030-7760-adcc-5e5d31b43d5d` | **SUCCEEDED** ~3 min; JPEG 2048² base colour; thumbnail: red apple with green leaf, yellow banana — **accepted**. Trimmed locally 3,038 → 2,998 tris (`tools/meshy_tutor_trim.py`, 0 credits). T2 total 15. |
| T3a | 2026-09-20 15:16:32Z | `cat_dog` | Text-to-3D **preview**, smart-topology `meshy-t2`, 2600 tris | `POST /openapi/v2/text-to-3d` | 5 | **5** | 3154 → 3149 | `01a0bf63-e681-701d-bdff-a38d0a186dbc` | **SUCCEEDED** 12s, 2,809 tris; thumbnail: sitting cat (ears, whiskers) beside sitting floppy-eared dog, clear gap — usable, refine approved |
| T3b | 2026-09-20 15:17:04Z | `cat_dog` | Text-to-3D **refine**, 2k texture, no PBR, on T3a | `POST /openapi/v2/text-to-3d` | 10 | **10** | 3149 → 3139 | `01a0bf64-61ff-7081-a154-3dbaf04849d9` | **SUCCEEDED** ~3 min; thumbnail: orange tabby with white muzzle + beagle-style tan/white puppy — **accepted** (cat's eyes slightly narrow; still unmistakably a cat). T3 total 15. |
| T4a | 2026-09-20 15:17:18Z | `number_blocks` | Text-to-3D **preview**, smart-topology `meshy-t2`, 2600 tris | `POST /openapi/v2/text-to-3d` | 5 | **5** | 3139 → 3134 | `01a0bf64-9d67-774f-8c81-7d1df655c930` | **SUCCEEDED** 18s, 2,547 tris; thumbnail: three touching rounded cubes with bold raised 1, 2, 3 — usable, refine approved |
| T4b | 2026-09-20 15:18:01Z | `number_blocks` | Text-to-3D **refine**, 2k texture, no PBR, on T4a | `POST /openapi/v2/text-to-3d` | 10 | **10** | 3134 → 3124 | `01a0bf65-28bb-7381-a687-705b4994647d` | **SUCCEEDED** ~3 min; thumbnail: blue 1, pink 2, yellow 3 in white raised numerals — **accepted**. T4 total 15. |

**Tutor props — final accounting (2026-09-20, 15:18Z).**

| | |
|---|---|
| Paid calls | 8 (4 previews at 5, 4 refines at 10) |
| Spent | **60** — table_set 15, fruit_set 15, cat_dog 15, number_blocks 15 |
| Rejected / written off | none; every preview passed its look-at-it review |
| Balance | 3184 → 3179 → 3169 → 3164 → 3154 → 3149 → 3139 → 3134 → **3124**; every delta matched the task's `consumed_credits` |
| Sprint ceiling | 100 authorised, **60 spent, 40 unspent** |

Runtime derivatives: `game/assets/tutor/props/*.glb`; raw masters:
`game/assets_source/meshy/tutor/` (gitignored). Details: `docs/TUTOR_MESHY_ASSETS.md`.

## 2026-09-21 — house props sprint (Agent C): no paid action

**Key unavailable.** `MESHY_API_KEY` was in neither the shell environment nor the macOS
keychain, so `GET /openapi/v1/balance` could not be called and **no task was created**.
Credits spent this session: **0**. Last verified balance stays **3124** (2026-09-20 15:18Z).
Sprint authorisation: 100, spent 60, **40 remain**; the next batch (teddy 15 + toy box 15 = 30)
is proposed in `docs/MESHY_PRODUCTION_PLAN.md` §6 and waits for the key and an explicit
"approved".

Zero-credit work recorded for provenance: `assets/tutor/props/fruit_set.glb` (tasks
`01a0bf62-ee3f-76db-84c7-3ae636d45f97` → `01a0bf63-9030-7760-adcc-5e5d31b43d5d`) was split locally
by `tools/meshy_split.py` into `assets/models/meshy-props/apple.glb` (1,120 tris) and
`banana.glb` (1,134 tris); both now stand in for the kitchen's drawn fruit.

## 2026-09-21 — house props batch (Agent D, branch `wt7/meshy2`)

**Observed balance delta, not a spend.** The key is now in the macOS keychain. First free read
this session: `GET /openapi/v1/balance` → HTTP 200 **3174** (09:42:23Z; the lead read the same
figure minutes earlier). The last recorded balance was **3124** (2026-09-20 15:18Z, after the
tutor props) and no paid call was made in between by any agent, so the **+50 is an account
top-up by the owner**, recorded here as an observation. Running totals below start from 3174.

**Authorisation for this batch:** the previously proposed pair, **at most 40 credits total**:
(1) teddy, (2) toy box with a separately movable lid — one text-to-3D task each at Smart Topology
(preview 5 + refine 10 = 15; the `consumed_credits` the API reports is checked against that
before the second asset is started). Bottle, cup and blocks are **not** in this batch. Rules
applied per paid call: balance before → expected cost stated → exactly one call → balance after
→ row below. A preview whose thumbnail does not read is not refined; a poor generation gets one
improved prompt, then stop.

Rows appended by `tools/meshy_batch.sh` from here on use this layout (letter `B` marks the
batch tool):

| # | Time (UTC) | Asset | Operation | Est. | Actual | Balance before → after | Task id | Outcome |
|---|---|---|---|---|---|---|---|---|
| B | 2026-09-21T09:43:12Z | teddy | text-to-3D preview, smart-topology meshy-t2, 2400 tris | 5 | 5 | 3174 → 3169 | `01a0c359-0d64-729f-98fe-4f3d84b4a8b6` | **SUCCEEDED** 30s, `consumed_credits` 5, 2,599 tris, 15 components; thumbnail reviewed (sitting bear, round head, ears, snout, arms out, legs forward) — usable, refine approved |
| B | 2026-09-21T09:43:41Z | teddy | text-to-3D refine, 2k texture, no PBR | 10 | 0 | 3169 → 3169 | `01a0c359-7b16-71a1-b767-ec7be3cbce06` | **SUCCEEDED** ~80s, `consumed_credits` 10 (the 2-second re-read showed delta 0; the deduction landed on completion: balance 3159 at 09:44:44Z, so 3169 → **3159**); caramel plush, cream muzzle/belly/paws, dark eyes — **accepted**. Teddy total 15. |
| B | 2026-09-21T09:46:57Z | toyBox | text-to-3D preview, smart-topology meshy-t2, 2200 tris | 5 | 5 | 3159 → 3154 | `01a0c35c-7baf-711a-a2df-d5991cf5a092` | **SUCCEEDED** 20s, `consumed_credits` 5, 1,982 tris, 58 components. Meshy drew the box **open** (lid up on back hinges) although the prompt said closed; the lid is its own 6-component group, so the split is *easier*, and the closed pose is a free local rotation. Thumbnail + free preview-GLB render reviewed — usable, refine approved |
| B | 2026-09-21T09:50:17Z | toyBox | text-to-3D refine, 2k texture, no PBR | 10 | 10 | 3154 → 3144 | `01a0c35f-8605-77b3-bfde-f5b08153c4a4` | **SUCCEEDED** ~3 min, `consumed_credits` 10; mint body, pale lid, peach handles/feet/hinges — **accepted**. Split locally into `toyBoxBody` (1,820 tris) + `toyBoxLid` (162 tris, closed, hingeBack). Toy box total 15. |

**House props batch — final accounting (2026-09-21, 09:51Z).**

| | |
|---|---|
| Paid calls | 4 (2 previews at 5, 2 refines at 10) |
| Spent | **30** — teddy 15, toyBox 15 (of the 40 authorised; **10 unspent**) |
| Rejected / written off | none; both previews passed their look-at-it review; no re-prompt was needed |
| Balance | 3174 → 3169 → 3159 → 3154 → **3144**; every delta matched the task's `consumed_credits` (the teddy refine's charge appeared a few seconds late, see its row) |
| Pricing check | preview 5 + refine 10 = 15 per asset, unchanged from the 2026-09-20 price list; the second asset was started only after the first had cost exactly 15 |
| Sprint ceiling | 100 authorised: 60 (tutor props) + 30 (this batch) = **90 spent, 10 unspent** |

Runtime derivatives: `game/assets/models/meshy-props/{teddy,toyBoxBody,toyBoxLid}.glb`; raw
masters: `game/assets_source/meshy/props/` (gitignored). Results and the next-batch proposal:
`docs/MESHY_PRODUCTION_PLAN.md` §8–§9. Not authorised and not run: bottle, cup, blocks.

## V3 bottle production — 2026-09-21

Official pricing verified before generation at https://docs.meshy.ai/en/api/pricing:
Smart Topology preview **5**, 2k refine **10**. API parameters verified at
https://docs.meshy.ai/en/api/text-to-3d. Account authenticated by HTTP 200 balance.

Pre-call plan recorded 16:06 UTC: `babyBottle` preview, `meshy-t2`, triangle
topology, target 2400, base pivot, GLB. Estimated 5 credits; **authorised** by
the owner's explicit V3 continuation. Refine estimate 10 credits, conditional
on reviewed recognizable geometry. Local texture optimization to 512 and
triangle gate <=3000 are free. No automatic retry.

| # | Time (UTC) | Asset | Operation | Est. | Actual | Balance before → after | Task id | Outcome |
|---|---|---|---|---|---|---|---|---|
| B | 2026-09-21T16:06:09Z | babyBottle | text-to-3D preview, smart-topology meshy-t2, 2400 tris | 5 | 5 | 3144 → 3139 | `01a0c4b7-a4d7-7122-ae7d-df89a4193e09` | SUCCEEDED, consumed_credits 5; inspected docs/shots/v3_bottle_preview.png: symmetric bottle, rounded base, distinct collar and teat; accepted for refine |

Refine pre-call record (16:07 UTC): accepted preview above; one 2k non-PBR
texture request, estimated **10 credits**, authorised. Palette: pale powder-blue
body, lavender collar, warm ivory teat, tiny pastel star decoration; no labels
or faces. Preserve empty/milk variant in runtime. No geometry retry needed.

| # | Time (UTC) | Asset | Operation | Est. | Actual | Balance before → after | Task id | Outcome |
|---|---|---|---|---|---|---|---|---|
| B | 2026-09-21T16:07:03Z | babyBottle | text-to-3D refine, 2k texture, no PBR | 10 | 10 | 3139 → 3129 | `01a0c4b8-729d-70c9-84b2-808fb844173c` | SUCCEEDED, consumed_credits 10; inspected docs/shots/v3_bottle_refined.png; accepted soft blue body, lavender collar, ivory teat; installed and imported |

**V3 final paid accounting (16:09:13 UTC):** balance **3144 → 3129**, actual
spend **15 credits**, exactly two paid calls, zero retries, zero paid remeshes.
Final balance independently reverified through authenticated balance endpoint.

Accepted GLB: `game/assets/models/meshy-props/babyBottle.glb` (139444 bytes),
2552 triangles, one surface/material, 512x512 JPEG. Height 0.25m, footprint
0.0872m square, base Y=0 and footprint centered on X/Z. Material roughness0.9,
metallic0, no emission/PBR maps. Raw masters remain gitignored under
`game/assets_source/meshy/props/babyBottle{Preview,}_v01.glb`.

Validation: Godot import completed; `test_assets_models` PASS, including actual
triangle count, texture dimensions, single surface, bounds and provenance.
Integration: shared `babyBottle` prop is bound to the existing `bottle` and
`bottleOfMilk` routes; root owns fill/collision/socket gameplay verification.
Exact 1334x750 Godot renders compare original 0.1.1 procedural geometry with
the live kitchen factory: `docs/shots/v3_before_bottle.png` and
`docs/shots/v3_after_bottle.png`, reproduced by `tests/shots_bottle_v3.gd`.
Final gameplay render and parity result belong in `docs/VISUAL_PRODUCTION_V3.md`.
Asset review screenshots: `docs/shots/v3_bottle_preview.png` and
`docs/shots/v3_bottle_refined.png`.
