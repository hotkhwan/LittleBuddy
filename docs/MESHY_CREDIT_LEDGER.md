# Meshy Credit Ledger

Every credit-consuming Meshy operation is recorded here **before** it is run, and updated after.
No generation task may be created that does not appear in this table.

**Running total spent by this session: 10 credits.** (Overnight WOW pass: owner set a **30-credit total ceiling** on 2026-09-19 with autonomous authority inside it. Overnight spend so far: see rows 3+.) (Balance 3079 → **3069**, verified before and
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

| 5 | 2026-09-19 | pinkGirl (`pinkGirl_remesh_v02`) | Rigging via `input_task_id` `01a0b5e9-6dae-7430-ac20-493219f3bfce` | `POST /openapi/v1/rigging` | 5 | — | **PLANNED — about to run** | — | `test_buddy_avatar.gd` gates `ENABLED` on the asset being in budget AND able to animate. The budget half now passes; the rig half does not, because she has no skeleton. The alternative was to relax that guard to allow a static avatar -- but the owner's brief says not to weaken tests to turn them green, and rigging gives a genuinely better result (idle pose plus free walk/run) for the same 5 credits. Overnight total after this: **15 of 30**. |

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
