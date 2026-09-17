# Nursery Swap Contract

How to replace the room's art without touching gameplay or interaction logic.

The current nursery uses **Kenney Furniture Kit** retinted to pastel. The intended upgrade is
**Tiny Treats "Playful Bedroom"** ($7.95, CC0), which is a much closer match to the soft-toy
pastel target but must be bought and downloaded by a human (itch.io browser flow).

This document defines the boundary so that swap is an art change only.

---

## The boundary, as it actually stands

**Gameplay anchors do not reference room geometry at all.** Verified in
`game/scenes/baby_room/baby_room.gd`:

- `MouthDropZone` and `HugDropZone` are positioned every frame from
  `BabyView3D.get_mouth_position()` / `get_hug_position()`, which derive from live marker-node
  transforms on the baby. They never read a room node name, and there is a fallback constant
  if those methods are ever missing.
- Object spawn points come from the activity scenes (`res://scenes/activities/*.tscn`), not
  from the nursery.
- The camera lives in `baby_room.tscn` and is aimed in code via `look_at_from_position()`.
- `baby_room.gd` touches the nursery in exactly one place — it instantiates
  `res://scenes/nursery/nursery_props.tscn` guarded by `ResourceLoader.exists()`, and frees
  its **own** fallback geometry when that succeeds.

So a replacement nursery only has to satisfy the contract below.

---

## What `res://scenes/nursery/nursery_props.tscn` MUST provide

1. Root is a **`Node3D`**.
2. It supplies the scene's **`WorldEnvironment`** and **exactly one `DirectionalLight3D`**.
   The project's performance budget allows one light; adding a second is a regression.
3. **Set dressing only.** No `Camera3D`, no `Area3D`, no UI/`CanvasLayer`, no `RigidBody3D`,
   no particles, and nothing interactive. Gameplay owns all of those.
4. It must leave the **play volume clear**: `x ∈ [−0.8, 0.8]`, `y ∈ [0, 1.0]`,
   `z ∈ [−0.4, 0.8]`. That is where the baby, the bottle, the teddy and spawned props live.
   Props intruding into it will intersect gameplay objects.
5. The room must stay **visually enclosed at both supported aspects** — iPhone landscape
   (~2.17:1) and iPad landscape (~1.44:1). The camera sees a wider horizontal field on the
   phone; walls that only cover the iPad framing will show background at the edges.
6. **No forbidden rendering features**: GI/SDFGI/VoxelGI/LightmapGI, SSAO, SSIL, SSR, glow,
   volumetric fog, post-processing.

`game/tests/cases/test_nursery_contract.gd` asserts points 1–4 and 6 automatically, so a
non-conforming replacement fails the suite rather than breaking silently at runtime.

## What it must NOT assume

- Do not expect gameplay to look up any node by name inside the nursery. Nothing does.
- Do not parent gameplay objects under nursery nodes.
- Do not add a camera — `baby_room.tscn` owns framing.

---

## Swapping in Tiny Treats "Playful Bedroom"

1. Buy and download from <https://tinytreats.itch.io/playful-bedroom> (CC0; the itch
   `Asset license` field reads *"Creative Commons Zero v1.0 Universal"*). **Archive the pack
   page on the download date** for licence provenance.
2. Extract the `.GLTF` set into `game/assets/models/tiny-treats-playful-bedroom/`, keeping any
   texture folder **alongside** the models — like Kenney's, these packs reference their atlas
   externally and relatively.
3. Rebuild `nursery_props.tscn` from those models. Expect to re-centre: Kenney furniture pivots
   are **corners**, and Tiny Treats GLTFs arrive with a ~0.01 node scale. Each prop in the
   current scene already sits under a centring anchor `Node3D`, so that pattern carries over.
4. Retinting will mostly be unnecessary — Tiny Treats is already pastel. The current
   `nursery_props.gd` retint layer (albedo override by material name, with per-instance
   `metadata/tint` and `metadata/no_shadow` hooks) can be reduced to just the shadow hook.
5. Run the suite. `test_nursery_contract` will catch a stray camera, a second light, an
   interactive node, or a prop intruding into the play volume.
6. Re-render at 1278×590 and 1180×820 and **look at both** before accepting.

Nothing in `game/scripts/**`, `game/content/**` or `game/scenes/baby_room/**` should need to
change. If it does, the boundary has been broken and that is the bug.

---

## Known weaknesses of the current (Kenney) room

Recorded so the swap can be judged against them:

- The Kenney silhouette language has **hard edges and chamfers** that read as sharper than the
  rounded Food Kit props and the very round baby. Retinting fixed the palette completely; it
  could not fix the geometry. This is the main reason to swap.
- The **floor lamp** is the weakest object — a thin pole that nearly disappears at phone aspect.
- The **bookcase shelves are empty** except the top; the kit's `books` prop is 15 cm and looks
  lost at that depth.
- **Wall-art frames are small and low-contrast**; they fill space rather than add charm.
- `bookcaseClosedWide` **ships with no back panel** despite the name — a painted backing board
  was added as a workaround.
- The bed reads as a **low toddler daybed, not a cot**.
