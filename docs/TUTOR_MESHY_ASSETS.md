# Tutor teaching props — Meshy generation record

**Date:** 2026-09-20 (15:06Z – 15:22Z) · **Agent M** · **Credits spent: 60 of the 100-credit ceiling**
· Balance **3184 → 3124**, verified with `GET /openapi/v1/balance` (HTTP 200) before and after every paid call.

Four classroom props for Aliz Tutor Mode, the shapes primitives do worst: a table-and-chairs set,
a fruit pair, a cat-and-dog pair and 1-2-3 number blocks. Every one is imported, loadable, inside
the mobile prop budget and gated by `game/tests/cases/test_tutor_props.gd`.

## What shipped

| propId | Runtime file | Tris | Texture | Size on disk | Real size (`scaleToMetres`) |
|---|---|---|---|---|---|
| `table_set` | `game/assets/tutor/props/table_set.glb` | 2,853 | 512² JPEG | 160,632 B | 1.25 m wide |
| `fruit_set` | `game/assets/tutor/props/fruit_set.glb` | 2,998 | 512² JPEG | 202,804 B | 0.26 m wide |
| `cat_dog` | `game/assets/tutor/props/cat_dog.glb` | 2,809 | 512² JPEG | 212,644 B | 0.55 m wide |
| `number_blocks` | `game/assets/tutor/props/number_blocks.glb` | 2,547 | 512² JPEG | 185,536 B | 0.27 m wide |

All four together: **1.0 MB**, 11,207 triangles, four draw calls. Each is one mesh, one primitive,
one material (metallic 0, roughness 0.9, single-sided, no emissive, no PBR maps) and one base-colour
texture. Manifest: `game/content/tutor/props_manifest.json`. Godot's importer extracts each texture
to `<prop>_0.jpg` beside its GLB; those and the `.import` sidecars are committed so a fresh clone
loads them.

Meshy normalises every model to a 1.0 m X extent centred on the origin (it ignored
`origin_at: bottom`). The manifest therefore carries `scaleToMetres` and `baseY`, the model-space
floor; a consumer rests a prop on Y=0 with `position.y = -baseY * scaleToMetres`.
`game/tests/shots_tutor_props.gd` does exactly that for the shelf render.

## Renders (Godot 4.7.2, Forward Mobile, one `DirectionalLight3D`, no post-processing)

| | |
|---|---|
| `docs/shots/tutor_prop_table_set.png` | `docs/shots/tutor_prop_fruit_set.png` |
| `docs/shots/tutor_prop_cat_dog.png` | `docs/shots/tutor_prop_number_blocks.png` |
| `docs/shots/tutor_props_shelf.png` | all four at manifest scale on one shelf, 1334×616 |

Reproduce: `Godot --path game --script res://tests/shots_tutor_props.gd`.

## Ledger (mirrors `docs/MESHY_CREDIT_LEDGER.md`)

Tier chosen from the live price list (`docs.meshy.ai/en/api/pricing`, read 2026-09-20): Smart
Topology text-to-3D (`model_type: smart-topology`, `ai_model: meshy-t2`) — **5 credits preview +
10 credits refine (2k texture) = 15 per asset**. It is the cheapest tier that yields a usable
texture and it takes `target_polycount` directly, so the ~3,000-triangle budget was asked for at
generation time instead of paid for again as a remesh. Meshy-6 would have been 30 per asset.

| # | Time (UTC) | Asset | Op | Task id | Credits | Balance |
|---|---|---|---|---|---|---|
| T1a | 15:08:55 | table_set | preview, 2800 tris | `01a0bf5c-ef29-7008-90d4-e7de13bda01f` | 5 | 3184 → 3179 |
| T1b | 15:09:47 | table_set | refine, 2k, no PBR | `01a0bf5d-ba03-7253-99d1-5e4fa89e71bd` | 10 | 3179 → 3169 |
| T2a | 15:15:29 | fruit_set | preview, 2800 tris | `01a0bf62-ee3f-76db-84c7-3ae636d45f97` | 5 | 3169 → 3164 |
| T2b | 15:16:10 | fruit_set | refine, 2k, no PBR | `01a0bf63-9030-7760-adcc-5e5d31b43d5d` | 10 | 3164 → 3154 |
| T3a | 15:16:32 | cat_dog | preview, 2600 tris | `01a0bf63-e681-701d-bdff-a38d0a186dbc` | 5 | 3154 → 3149 |
| T3b | 15:17:04 | cat_dog | refine, 2k, no PBR | `01a0bf64-61ff-7081-a154-3dbaf04849d9` | 10 | 3149 → 3139 |
| T4a | 15:17:18 | number_blocks | preview, 2600 tris | `01a0bf64-9d67-774f-8c81-7d1df655c930` | 5 | 3139 → 3134 |
| T4b | 15:18:01 | number_blocks | refine, 2k, no PBR | `01a0bf65-28bb-7381-a687-705b4994647d` | 10 | 3134 → 3124 |

Every delta matched the task's `consumed_credits`. Eight paid calls, eight successes, **no
retries, no failures, nothing rejected**: each preview's thumbnail was downloaded (free) and looked
at before its refine was paid for, and all four passed. Previews took 11–19 s; refines 3–5 min.

### Judgement notes, per asset

* **table_set** — preview: round top, chunky legs, two chairs, exactly the brief. Refine: mint top,
  light-wood legs, one yellow and one pink chair. The flat top shows faint radial shading under
  a hard light because Meshy ships fully smooth normals on a triangle-fan top; acceptable for a
  toy, fixable later with a hard-edge split at zero cost if it bothers anyone.
* **fruit_set** — preview came back at **3,038 triangles, 38 over the 3,000 gate**. Rather than
  weaken the test or pay 5 credits for a remesh, `tools/meshy_tutor_trim.py` collapses the
  shortest same-UV edges locally: 24 collapses, 3,038 → 2,998, invisible in the render. The two
  later previews were requested at 2,600 to leave headroom, and landed at 2,809 and 2,547.
* **cat_dog** — an orange tabby with white muzzle and a tan/white floppy-eared puppy, sitting side
  by side with a clear gap. The cat's eyes came out narrower than the "big round kind eyes" the
  texture prompt asked for; it is still unmistakably a cat and reads well at shelf distance. The
  two animals are one primitive; splitting them into separate `cat` and `dog` props would need a
  local mesh split (no credits) and is left for whoever wires the lesson.
* **number_blocks** — blue 1, pink 2, yellow 3 with white raised numerals; the numerals are
  geometry, not just texture, so they survive at 512².

## Raw masters and re-download

Raw Meshy downloads (2.0–2.7 MB each, 2048² JPEG) are in `game/assets_source/meshy/tutor/`:
`<asset>_preview_v01.glb` (untextured preview) and `<asset>_v01.glb` (textured refine), plus
`fruit_set_v01_trim.glb`. That directory is gitignored and excluded by `export_presets.cfg`, so
nothing raw reaches the .pck or the repo. If a master is lost, any task id above re-downloads it
with `tools/meshy_tutor_text3d.sh fetch <taskId> <stem>` at zero credits while Meshy keeps the
task; the signed URLs were never written to any file.

Pipeline, all local: `meshy_tutor_text3d.sh fetch` → (`meshy_tutor_trim.py --max 3000` when
over) → `optimize_runtime_glb.py --texture 512` → `Godot --headless --import` →
`test_tutor_props.gd` → `shots_tutor_props.gd`.

## Licence and provenance statement

> These four models were generated on 2026-09-20 with Meshy's text-to-3D API under the owner's
> paid Meshy subscription, from prompts written for this project, with no reference images.
> Commercial use is per the plan's terms. Provenance evidence is the eight task ids above, which
> resolve on the owner's account via `GET /openapi/v2/text-to-3d/<id>`. The same statement is
> carried per prop in `props_manifest.json` (`license`, `meshyTaskIds`, `creditsSpent`) and is
> asserted by `test_tutor_props.gd`.

## Tooling written this round

* `tools/meshy_tutor_text3d.sh` — `balance | preview | refine | poll | wait | thumb | fetch`.
  Balance before and after, explicit `--yes` (a run without it prints the payload and exits 2
  having sent nothing), no retry, no overwrite, sentinel UUID refused, returned id compared to the
  requested id, key never printed. One fix over the reference script: `meshy_aliz_apose.sh`
  reads `HTTP_CODE` set inside a `$(...)` subshell, which is always unbound under `set -u`; it
  had never run with a key present. This tool passes the status through a temp file.
* `tools/meshy_tutor_trim.py` — same-UV shortest-edge collapse to a triangle budget, no credits.
* `game/tests/cases/test_tutor_props.gd` — loads every manifest GLB, instantiates it, counts
  triangles across all surfaces, checks texture size, metallic, emission, task ids, licence text,
  and that the manifest's `triangles`/`textureSize` match the file. Suite: **141 cases, 0 failures**.
* `game/tests/shots_tutor_props.gd` — the renders above.

## Not done / for the integrator

* No scene, script or `objects.json` record references these props yet — that is deliberate; this
  round only owned assets, manifest, tests and docs.
* `cat_dog` is one mesh. If the lesson needs "cat" and "dog" as separate touch targets, split it
  by connected component locally (both halves are well separated in X: cat is X<0, dog X>0).
* 40 credits of the ceiling remain unspent.
