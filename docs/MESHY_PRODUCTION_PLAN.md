# Meshy 3D production plan — house props

**Date:** 2026-09-21 · **Agent C** (plan, `wt6/meshy`) → **Agent D** (batch 1 run, `wt7/meshy2`) · Godot 4.7.2

> **Batch 1 is DONE (2026-09-21, Agent D): teddy + toy box (body and lid), 30 of the 40 authorised
> credits.** The key now lives in the macOS keychain (`security find-generic-password -s
> MESHY_API_KEY -w`); `tools/meshy_batch.sh` reads it per call and never prints it. Results in
> §8, next-batch proposal in §9. The earlier "BLOCKED: no key" note is kept below for the record.

> *(Superseded 2026-09-21)* **BLOCKED: no MESHY_API_KEY on this machine** — the key was not in the
> shell environment or the keychain when Agent C planned this; no paid call was made then.
> Every new tool (`tools/meshy_batch.sh`) reads the env var first and falls back to the keychain
> item; with neither it fails closed with a one-line instruction. The key is never printed,
> logged or committed, and signed URLs are never written to a file.

What was done without credits is real and shipping: the tutor's Meshy **fruit set was split
locally into a separate apple and banana**, and the kitchen now draws those two GLBs
(`docs/shots/props_items_ipad.png`, `kitchen_2_fridge_open.png`, `kitchen_3_take_banana.png`)
with the drawn primitives kept as the fallback. Suite: `PASS - 159 case(s)`.

---

## 1. Inventory — what exists, what stands in, what needs generating

Sources read: `docs/ASSET_MANIFEST.md`, `docs/MESHY_CHARACTER_AUDIT.md`,
`docs/MESHY_CREDIT_LEDGER.md`, `docs/TUTOR_MESHY_ASSETS.md`, `game/content/tutor/props_manifest.json`,
`game/content/objects.json`, every GLB under `game/assets` (28 files; no `.tres` ArrayMesh
assets exist — all house geometry is `SurfaceTool` code in `prop_kit.gd` / `room_props.gd` /
`room.gd` / `kitchen_view.gd`).

Real Meshy GLBs already in the repo (2026-09-20, 15 credits each, one mesh / one 512² texture):

| file | tris | components (local split, free) |
|---|---|---|
| `assets/tutor/props/fruit_set.glb` | 2,998 | banana 1,134 · apple 764 (+744 inner shell, dropped) · leaf 178 · stem 178 |
| `assets/tutor/props/number_blocks.glb` | 2,547 | 8 (two block bodies + numerals) |
| `assets/tutor/props/cat_dog.glb` | 2,809 | cat 1,206 + parts · dog 1,128 + parts — splits cleanly |
| `assets/tutor/props/table_set.glb` | 2,853 | 17 (top, legs, two chairs) |

Kenney CC0 GLBs (Baby Room spawns via `object_spawner.gd`): apple, banana, bowl, carton, cup,
glass, spoon, polar bear (= teddy, tinted), ball, furniture kit (bed, bookcase, box, lamps, plants,
rug). Characters: Meshy pinkGirl / baby runtime derivatives (out of scope here).

### Owner priority list → status

| asset | exists (path) | duplicate risk | verdict |
|---|---|---|---|
| **apple** | Kenney `kenney-food-kit/apple.glb` (Baby Room); kitchen was `_draw_apple()` primitive | tutor `fruit_set` shows the same apple on the classroom table | **DONE, 0 credits** — `assets/models/meshy-props/apple.glb` split from the fruit set; kitchen uses it |
| **banana** | Kenney banana (Baby Room); kitchen was `_draw_banana()` | as above | **DONE, 0 credits** — `meshy-props/banana.glb` |
| bottle | kitchen `_draw_bottle()` (two words: `bottle`, `milk`); Baby Room milk = Kenney carton | none | needs generation (2 looks: empty bottle + milk-filled) — batch 3 |
| cup | Kenney cup (Baby Room, bath) | none | keep Kenney (CC0, reads well) |
| spoon | Kenney spoon + kitchen `_draw_spoon()` | none | keep; weakest Kenney silhouette but a Meshy spoon is the same small detail |
| bowl | Kenney bowl + kitchen `_draw_bowl()` / dishes | none | keep |
| toy blocks | `proc/blocks` (procedural, green, `colorWord: green`) | tutor `number_blocks` | **do not stand in**: the number blocks are blue/pink/yellow with numerals; the record teaches "green block". A plain 3-colour block stack would need its own generation — batch 3 |
| **teddy** | Kenney `animal-polar` tinted brown (cube bear) | none | **generate — priority 1** (bedtime, tidy-up, hug; the most-seen toy) |
| **toy box** | bedroom storage: drawn body + hinged lid (`room.gd::_build_storages`); Baby Room `toyBox` = Kenney `cardboardBoxOpen` | none | **generate body + lid — priority 2** (one task, split locally, `pivot: hingeBack`) |
| fridge | drawn body, split-high doors (`room_props._fridge`); kitchen door hinge in `kitchen_view.gd` | none | generate body + door (one task, split) — batch 3 |
| wardrobe | drawn body + two hinged leaves (`_build_wardrobe_doors`, `_openables`) | none | generate body + 2 doors (one task, split, `hingeLeft`/`hingeRight`) — batch 3 |
| kitchen counter | drawn (`_counter`) — prep surface heights come from the layout box | none | later; must be sized to the layout box exactly |
| bathtub | drawn (`_bath`, vessel primitive) | none | later |
| sink | drawn (`_sink`) | none | later |
| table | drawn (`_table`), kitchen; food rests at `_table_top()` | tutor `table_set` | **not a stand-in**: brings two chairs onto Aliz's stand point and a different top height |
| trees / flowers / cottage details | menu garden primitives | none | later; one "pastel tree", one "flower clump", one "cottage door + window" set |
| cat, dog | tutor `cat_dog.glb` | tutor | free split available (`meshy_split.py --parts cat,dog`) when the house needs pets |

## 2. Prompts (house style)

Style suffix appended by `tools/meshy_batch.sh` to every prompt: *"Soft pastel low-poly toy
style for a children's storybook game, single object, neutral pose, gently rounded shapes,
matte colours, plain background, no text, no logos, no people."* Tier: Smart Topology
(`meshy-t2`), `target_polycount` set per asset, refine at 2k texture, no PBR, downsampled to
512² locally. **No brand, studio or artist names** (ART_BIBLE §11).

| asset | preview prompt | texture prompt | `--tris` | gate |
|---|---|---|---|---|
| teddy | "A cuddly teddy bear sitting upright, round head, small round ears, short arms held slightly out, stubby legs forward, soft plush body" | "Warm caramel-brown plush fur, pale cream muzzle and inner ears, small dark friendly eyes and nose, no stitching detail" | 2,400 | 2,600 (→ split? no; single part) |
| toy box | "A child's wooden toy box with a separate closed hinged lid resting on top, rectangular, slightly rounded corners, small handle bar on the lid, lid is a distinct piece with a visible seam" | "Mint green painted wood, cream lid with a peach handle, soft matte paint" | 2,200 | body ≤ 1,600 + lid ≤ 800 |
| fridge | "A tall single-door child's play kitchen fridge, one large door with a small freezer door above it, both doors closed with visible seams, a long vertical handle" | "Mint green matte paint, cream handles, no logos" | 2,400 | body ≤ 1,600 + door(s) ≤ 900 |
| wardrobe | "A tall wooden child's wardrobe with two closed doors meeting in the middle, round knobs, small feet, a simple cornice" | "Light honey wood, lavender door panels, cream knobs" | 2,600 | body ≤ 1,600 + 2 doors ≤ 500 each |
| bottle | "A baby bottle standing upright, wide body, collar and teat, simple rounded shape" | "Translucent-looking pale cream body painted opaque, soft pink collar and teat" | 1,200 | 1,200 |
| blocks | "Three toy building blocks, two side by side and one stacked on top, plain faces, no letters" | "Soft green in three close shades, matte painted wood" | 1,200 | 1,200 |
| tree | "A round pastel storybook tree, chunky short trunk, one big soft rounded canopy" | "Mint-green canopy, light wood trunk" | 1,000 | 1,000 |
| flowers | "A small clump of three simple round flowers on short stems with two leaves" | "Pink, yellow and lavender petals, mint leaves" | 900 | 900 |

`target_polycount` is a target, not a ceiling (the fruit set came back 38 over); the local
trimmer can remove roughly 5–10% (same-UV edges only — the dry run shows the banana stops at
1,068 from 1,134), so ask 10% under the gate.

## 3. Openable furniture — moving parts

Two routes, both supported by the pipeline; **route A is the default**:

- **A. One task, split locally (15 credits).** Prompt for "doors closed with visible seams".
  Meshy's Smart Topology keeps a door that reads as a separate slab as its own connected
  component (every prop we own splits cleanly: 5/8/14/17 components). `tools/meshy_split.py
  --parts body,door --assign …` writes one GLB per part with the same 512² texture; the door
  gets `pivot: hingeLeft` (or `hingeBack` for a lid) in the manifest so `prop_registry.gd`
  places its origin on the hinge edge. `room.gd` then hangs it under the **same** hinge node it
  uses today (`WardrobeDoor_L/R`, `StorageLid_<id>`), and `set_open()` / `set_storage_open()`
  rotate exactly as before. If a door does NOT come back as a separate component, the fallback
  is `--assign` by index after `--list`, and if it is welded to the body, route B.
- **B. Two tasks (30 credits).** Body with an open recess + door as separate generations.
  Only when A fails; costs a second texture and twice the credits.

Splitter: `tools/meshy_split.py` (pure stdlib; trimesh/numpy are not installed here). Proven on
the fruit set (apple + banana, inner shell dropped) and listed on the other three.

## 4. Pipeline (works end to end without credits)

`tools/meshy_batch.sh`: `balance | preview | refine | poll | wait | thumb | fetch | install`.
Paid steps: balance before → one call → balance after → row appended to
`docs/MESHY_CREDIT_LEDGER.md` (task id, cost, before → after, outcome); `--yes` required, cost
checked against `MESHY_AUTHORISED_REMAINING` (default 40); no retry; sentinel and id-mismatch
refused. Local tail: `meshy_split.py` (parts, pivot, metres) → `meshy_trim.py` (gate, all
primitives) → `optimize_runtime_glb.py` (512² texture, §7 material) → gate re-read **off the
written file** → copy to `game/assets/models/meshy-props/<part>.glb` → manifest row → `Godot
--headless --import`.

Dry run, proven on the existing fruit set:

```
tools/meshy_batch.sh install fruit_set_dryrun game/assets/tutor/props/fruit_set.glb \
    --parts banana,apple --scale 0.26 --max-tris 1200 --task-ids <two ids> --dry-run
```

→ banana 1,134 tris, apple 1,120 tris, base y = 0.000, manifest rows printed, nothing under
`game/` touched. The same run at `--max-tris 1000` **fails the gate correctly** (1,068 after
every collapsible edge). Known cosmetic bug in the pre-existing `optimize_runtime_glb.py`: it
prints a nonsense JPEG size ("4718592x…") for these files; the 512² limit is asserted by
`test_assets_models.gd` on the imported texture regardless.

Attach contract per asset: `tools/meshy_attach.md`.

## 5. Attached this round (0 credits)

| prop | file | tris | seam | shot |
|---|---|---|---|---|
| apple | `game/assets/models/meshy-props/apple.glb` | 1,120 | `kitchen_items.gd` `"model": "apple"` → `kitchen_view.gd::_make_item()` → `prop_registry.gd` | `docs/shots/props_items_ipad.png`, `props_silhouette_ipad.png`, `kitchen_2_fridge_open.png` |
| banana | `game/assets/models/meshy-props/banana.glb` | 1,134 | same, `"model": "banana"` | `kitchen_3_take_banana.png`, `kitchen_4_on_counter.png` |

Fallback: `_draw_apple()` / `_draw_banana()` stay in `kitchen_view.gd` and are used whenever
the registry returns `null` (no manifest row, file missing, import failed). Budget: kitchen item
row 1,660 → 3,830 tris; one light, no GI, unchanged. Tests added to
`game/tests/cases/test_assets_models.gd` (`_test_meshy_props`, `_test_kitchen_models_resolve`).

## 6. Proposed next batch — for owner approval

Balance math: last verified balance **3124** (2026-09-20 15:18Z, after the tutor props). Sprint:
100 authorised, 60 spent, **40 remain authorised**. Nothing spent since; the live balance cannot
be read here without the key.

| # | asset | operation | expected credits | priority | running balance |
|---|---|---|---|---|---|
| 1 | teddy | preview 5 + refine 10 | 15 | 1 | 3124 → 3109 |
| 2 | toy box body + lid (one task, split locally) | preview 5 + refine 10 | 15 | 2 | 3109 → 3094 |
| | **total this request** | | **30 of the 40 authorised** | | **3124 → 3094**, 10 left unspent |

Stop rule: two refined assets, then STOP. A preview whose thumbnail does not read (looked at
via `meshy_batch.sh thumb`, free) is **not** refined: 5 written off, 10 saved, ledger row says
rejected, no retry without a new approval.

Following batch (needs a fresh authorisation, not requested now): fridge body+door 15, wardrobe
body+2 doors 15, bottle 15, blocks 15, tree 15, flowers 15 = 90.

## 7. Blockers and notes

- ~~BLOCKED: no MESHY_API_KEY on this machine~~ — resolved 2026-09-21; the key is in the keychain.
- `objects.json` (content) is not owned by this agent: pointing the Baby Room `teddy` record at
  a Meshy teddy is a one-field change for the content owner once the asset exists; the loader
  change it needs is described in `tools/meshy_attach.md`.
- Untracked `game/assets/ui/generated_v1/**/*.png.import` files appeared from `--import` (the UI
  pack commit shipped without sidecars); left untracked, not this agent's files.
- No device claims: renders are Godot 4.7.2 Forward Mobile on macOS via the shot harnesses.

## 8. Batch 1 results (2026-09-21, Agent D, branch `wt7/meshy2`)

Balance 3174 → **3144**; 30 credits; four paid calls, each ledgered
(`docs/MESHY_CREDIT_LEDGER.md`, rows `B`). Suite after install: `PASS - 163 case(s), 0 failure(s)`.

| asset | verdict | task ids (preview → refine) | file | tris / gate | texture | size | shot |
|---|---|---|---|---|---|---|---|
| **teddy** | **accepted** — sitting bear, round head, ears, snout, arms out, legs forward; caramel plush, cream muzzle/belly/paws, dark eyes, no text | `01a0c359-0d64-729f-98fe-4f3d84b4a8b6` → `01a0c359-7b16-71a1-b767-ec7be3cbce06` | `game/assets/models/meshy-props/teddy.glb` | 2,599 / 2,600 (no trim needed) | 512² JPEG | 0.30 m tall, 20 × 30 × 25 cm, faces +Z | `docs/shots/props_meshy_ipad.png`, `props_meshy_turn_ipad.png`, `props_meshy_silhouette_ipad.png` |
| **toy box body** | **accepted** — chest with corner feet, side handles, top rim; mint / peach | `01a0c35c-7baf-711a-a2df-d5991cf5a092` → `01a0c35f-8605-77b3-bfde-f5b08153c4a4` | `meshy-props/toyBoxBody.glb` | 1,820 / 2,000 | 512² JPEG (shared with the lid) | 0.700 × 0.353 × 0.475 m | same row shots + `props_toybox_closed_ipad.png`, `props_toybox_open_ipad.png` |
| **toy box lid** | **accepted** — separate slab with frame and peach pull bar, `pivot: hingeBack` | same task | `meshy-props/toyBoxLid.glb` | 162 / 400 | shared | 0.588 wide × 0.076 × 0.473 deep | as above |

What happened with the lid, because it is the thing the next furniture batch will hit again:
Meshy generated the box **open** — lid up ~100° on two back hinges — despite "closed, lid resting
on the body with a visible seam". That is the *good* outcome for a split: the lid came back as
its own 6-component group (162 tris) and the knuckles stayed on the body, so route A (one task,
split locally) worked without a re-prompt. The lid was then posed closed for free:
`tools/meshy_split.py` gained per-part `--rotate-x` (100.5°, measured by PCA of the lid slab),
`--stretch z:1.25` (the generated lid was ~20 % shorter than the opening; a flat slab does not
show a length stretch) and `--part-origin hingeBack`; `tools/meshy_batch.sh install` gained
`--pivot part=hingeBack` (manifest row + written-file pivot check) and `--split-args`
passthrough, and `--assign` accepts `*=part` for "everything else". The exact command is in each
manifest row's `derivedFrom.args`, so both parts regenerate from the master with no credits.

Assembled check (`tests/shots_props.gd -- ipad 1334x750 meshy`, `_assemble_toy_box`): body on
the floor, lid under a `StorageLid_toyBox` hinge node at the manifest's
`attach.hingeOffsetMetres = (0, 0.337, −0.202)` from the body origin; the closed lid's
underside sits 1.6 cm *below* the rim top (the generated lid drops into the rim like an inset
lid, which is how Meshy modelled it), and it reaches the front rim. Opened −104° (the layout's
`openDegrees`) it clears the opening.

**Not wired** (Agent E, per the brief). Suggested attach points are in each manifest row's
`attach` object:

- `teddy` → bedroom prop `teddy` via `PropRegistry.instance("teddy", 0.30)`; Baby Room
  `objects.json` `teddy.model` → `meshy-props/teddy`. Caveat: `object_spawner.gd`'s spawned-model
  cap is 600 triangles (`test_assets_models.gd::_test_mesh_budget`); this teddy is 2,599. Either
  raise the cap for the `meshy-props` pack with the owner's agreement, or derive a Baby Room LOD
  locally (the same-UV edge collapse in `meshy_trim.py` will not reach 600 from 2,599 without
  visible damage; a 5-credit remesh at `target_polycount` ~300 quads is the honest route).
- `toyBoxBody` → `room.gd::_build_storages` toyBox body in place of `Kit.commit(body_tool)`;
  `toyBoxLid` → the `Lid` mesh under the SAME `StorageLid_toyBox` hinge node, hinge moved to the
  body's real top-back line (`attach.hingeOffsetMetres`); `set_storage_open()`'s X-rotation
  tween is untouched. The generated body is 0.353 m tall against the layout box's 0.50: the
  collider and stand point come from the layout, so either accept the shorter box or size the
  body by height (`PropRegistry.instance("toyBoxBody", 0.99)` would make it 0.50 tall but 0.99
  wide — too wide; better to accept 0.353 and lower the hinge).

## 9. Proposed batch 2 — for owner approval (not authorised, not run)

Balance **3144** (2026-09-21 09:51Z). Sprint: 100 authorised, **90 spent, 10 unspent** — batch 2
needs a fresh authorisation. Same tier (Smart Topology preview 5 + refine 10), same stop rules,
same one-task-split-locally route for anything that opens.

| # | asset | operation | est. credits | priority | why | running balance |
|---|---|---|---|---|---|---|
| 1 | bottle (baby bottle, empty; `bottleOfMilk` stays drawn or gets a second look later) | preview + refine | 15 | 1 | kitchen `_draw_bottle()` is the weakest kitchen silhouette; two words hang on it | 3144 → 3129 |
| 2 | cup | preview + refine | 15 | 4 | Kenney CC0 cup already reads well — lowest value; include only if the owner wants one collection look | 3129 → 3114 |
| 3 | blocks (three plain green blocks, no numerals) | preview + refine | 15 | 2 | `proc/blocks` teaches "green block"; the tutor number blocks cannot stand in (numerals, wrong colours) | 3114 → 3099 |
| 4 | fridge body + door (one task, split; prompt "door slightly ajar" given the toy-box lesson) | preview + refine | 15 | 3 | kitchen hero prop; `kitchen_view.gd` door hinge exists | 3099 → 3084 |
| 5 | wardrobe body + 2 doors (one task, split, `hingeLeft`/`hingeRight`) | preview + refine | 15 | 5 | bedroom; `_build_wardrobe_doors` hinges exist | 3084 → 3069 |
| 6 | tree (menu garden) | preview + refine | 15 | 6 | menu WOW; one canopy + trunk | 3069 → 3054 |
| 7 | flowers (clump of three) | preview + refine | 15 | 7 | menu garden accent | 3054 → 3039 |
| | **total if all seven** | | **105** | | | **3144 → 3039** |

Recommended first slice if the owner prefers a smaller number: bottle + blocks + fridge = **45**.
Lesson to carry into the prompts: for anything hinged, ask for "slightly ajar, small gap" rather
than "closed with a seam" — Meshy ignored "closed" and produced an open lid, which split cleanly;
a truly closed lid welded to the body would have needed route B (two tasks, 30 credits).
