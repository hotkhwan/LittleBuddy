# Meshy 3D production plan — house props

**Date:** 2026-09-21 · **Agent C** · branch `wt6/meshy` · Godot 4.7.2

> **BLOCKED: no MESHY_API_KEY on this machine**
>
> `MESHY_API_KEY` is not in the shell environment and not in the macOS keychain
> (`security find-generic-password -s MESHY_API_KEY -w` finds nothing). No paid call was
> made, no balance was read, **0 credits were spent**; the 40 authorised credits are
> untouched. To unblock, the owner runs once, on this MacBook:
>
> ```
> security add-generic-password -s MESHY_API_KEY -a littledays -w '<key>'
> ```
>
> Every new tool (`tools/meshy_batch.sh`) reads the env var first and falls back to that
> keychain item; with neither it fails closed with that one-line instruction. The key is
> never printed, logged or committed, and signed URLs are never written to a file.

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

- **BLOCKED: no MESHY_API_KEY on this machine** — see the top of this file.
- `objects.json` (content) is not owned by this agent: pointing the Baby Room `teddy` record at
  a Meshy teddy is a one-field change for the content owner once the asset exists; the loader
  change it needs is described in `tools/meshy_attach.md`.
- Untracked `game/assets/ui/generated_v1/**/*.png.import` files appeared from `--import` (the UI
  pack commit shipped without sidecars); left untracked, not this agent's files.
- No device claims: renders are Godot 4.7.2 Forward Mobile on macOS via the shot harnesses.
