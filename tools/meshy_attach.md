# Attaching a Meshy prop to gameplay

How each generated asset reaches the screen, which script owns the seam, and what
the primitive fallback is. Companion to `docs/MESHY_PRODUCTION_PLAN.md` (what to
generate) and `tools/meshy_batch.sh` (how to generate and install).

## The one seam: `game/scripts/house/prop_registry.gd`

Every house-side consumer asks the registry, never a file path:

```gdscript
const PropRegistry := preload("res://scripts/house/prop_registry.gd")

var node: MeshInstance3D = PropRegistry.instance("apple", 0.20)   # longest axis 0.20 m
if node == null:
    # draw the primitive exactly as before
```

`instance()` returns `null` for anything short of "manifest row + GLB imported +
mesh has triangles", so a missing or broken file can only ever cost a nicer prop,
never the prop. The returned mesh is baked (node transforms applied), in metres,
one surface, materials kept (section 7 policy applied), and sits on its pivot:

| `pivot` in manifest | origin | for |
|---|---|---|
| `baseCentre` (default) | base on Y=0, footprint centred | anything that stands on a surface |
| `hingeLeft` | -X edge on X=0, Y/Z centred | wardrobe LEFT leaf, fridge door hinged left |
| `hingeRight` | +X edge on X=0, Y/Z centred | wardrobe RIGHT leaf |
| `hingeBack` | back edge on Z=0, base on Y=0, X centred | toy box / storage lid |

Manifest: `game/assets/models/meshy-props/manifest.json` (camelCase). One row per
prop: `propId`, `file`, `longestAxisMetres`, `yawDegrees`, `pivot`, `triangles`,
`maxTriangles`, `textureSize`, `meshyTaskIds`, `creditsSpent`, `license`,
`derivedFrom`, `usedBy`. `test_assets_models.gd::_test_meshy_props` asserts every
row against its file.

## Per asset

| asset | where it shows | seam (file, function) | fallback kept | status |
|---|---|---|---|---|
| **apple** | kitchen: fridge shelf, worktop, Aliz's hand, `props_items` row | `kitchen_items.gd` row `apple` → `"model": "apple", "modelSize": 0.20`; `kitchen_view.gd::_make_item()` asks the registry first | `_draw_apple()` | **live** (split from `fruit_set`, 0 credits) |
| **banana** | kitchen, same places | `kitchen_items.gd` row `banana` → `"model": "banana", "modelSize": 0.26` | `_draw_banana()` | **live** |
| bottle / bottleOfMilk | kitchen | same rows, `"model": "bottle"` when generated; `bottleOfMilk` stays drawn unless a filled variant is generated (two words, two looks — §6) | `_draw_bottle()` | not generated |
| cup | Baby Room spawn (`objects.json` → `kenney-food-kit/cup`) | `object_spawner.gd` `MODEL_PRESENTATION`; a Meshy cup would be a new pack entry `meshy-props/cup` with a `PACK_TEXTURES` entry of `""` and `surfaces` unused (the GLB carries its own texture) — needs a small loader change: textured non-atlas packs keep the imported material | Kenney cup | not generated; Kenney CC0 cup is fine |
| spoon, bowl | Baby Room (Kenney) + kitchen (`_draw_spoon`, `_draw_bowl`) | kitchen rows as above | drawn | not generated; low value |
| toy blocks | Baby Room / bedroom tidy-up (`objects.json` `blocks` → `proc/blocks`) | `object_spawner.gd` — see cup | procedural stack | **do not swap for `number_blocks`**: record is `colorWord: green`, the number blocks are blue/pink/yellow and carry numerals (a mis-teach) |
| **teddy** | Baby Room `dragToHug`, bedroom tidy-up, bedtime (`BEDTIME_TEDDY_ID`) | `objects.json` `teddy.model` → new `meshy-props/teddy`; loader change as for cup; `MODEL_PRESENTATION["meshy-props/teddy"] = {"size": 0.25, "rotation": Vector3(0, -18, 0)}` | Kenney polar bear tinted brown | **next batch, priority 1** |
| **toy box (body + lid)** | bedroom storage `toyBox` (`house_layout.storages`, `room.gd::_build_storages`) | body: `room.gd` where `Storage_<id>` mesh is built — `PropRegistry.instance("toyBoxBody", size.x)` in place of `Kit.commit(body_tool)`; lid: `PropRegistry.instance("toyBoxLid", size.x)` under the SAME `StorageLid_<id>` hinge node (`pivot: hingeBack`) so `set_storage_open()`'s X-rotation tween is untouched | drawn box + lid | **next batch, priority 2** (one task, split locally) |
| wardrobe (body + 2 doors) | bedroom `wardrobe` (`_build_furniture`, `_build_wardrobe_doors`) | body: `RoomProps.build()` branch → registry first; doors: `PropRegistry.instance("wardrobeDoorL", 0.40)` / `("wardrobeDoorR", 0.40)` as `Leaf` under each hinge (`pivot: hingeLeft/hingeRight`), swing maths in `set_open()` unchanged | drawn | later batch |
| fridge (body + door) | kitchen `fridge` (`room.gd::_build_furniture`; the kitchen's own door is `kitchen_view.gd` `DOOR_OPEN_DEGREES`) | body via `RoomProps.build()` seam; door under `kitchen_view.gd`'s door hinge (`pivot: hingeLeft`) | drawn | later batch |
| kitchen counter, sink, bathtub | kitchen / bathroom furniture | `RoomProps.build()` seam; the counter is the prep surface (`_anchor("counter")` heights come from `house_layout` size, so the GLB must be sized to the layout box) | drawn | later batch, low priority (drawn versions read well) |
| table | kitchen `table` | keep drawn: served food rests at `_table_top()` = layout height, and the tutor `table_set` brings two chairs onto Aliz's stand point | drawn | **not a stand-in** |
| trees, flowers, cottage details | menu garden / exterior (`test_menu_wow` garden cap) | menu scene builder | drawn | later batch |

## Wiring a room prop through `RoomProps.build()` (when the first furniture GLB lands)

`room.gd::_build_furniture()` does `if not RoomProps.build(tool, target_id, room_id, size): Kit.box(...)`,
then `_add_mesh("Prop_%s" % target_id, Kit.commit(tool))`. The minimal hook, four lines, no
layout number touched:

```gdscript
var swapped: MeshInstance3D = PropRegistry.instance(target_id, size.x)
if swapped != null:
    swapped.position = centre - Vector3(0.0, size.y * 0.5, 0.0)   # layout centre -> base
    _geometry.add_child(swapped)
else:
    ... existing SurfaceTool path
```

The collider, the `ActivityTarget` and the stand point come from the layout box as before;
the GLB is sized to the box's width so it fits the collider. Doors/lids go under the existing
hinge nodes with a hinge pivot, replacing only the `Leaf`/`Lid` `MeshInstance3D`.

## Wiring a spawned object (`objects.json`) to a Meshy prop

`object_spawner.gd` colours atlas packs with `material_override` (Kenney) and untextured packs
per surface. A Meshy GLB carries its own texture and must keep its imported material — that is
a third route: `pack_texture_path(pack) == ""` AND a surface material with an `albedo_texture`
→ leave the material alone. Add `"meshy-props": ""` to `PACK_TEXTURES`, the presentation row,
and set `"model": "meshy-props/teddy"` in `objects.json` (content — owner of that file applies
it). `test_assets_models.gd::_test_mesh_budget` caps spawned models at 600 tris; a Meshy teddy
must be generated at `--tris 550` and trimmed to fit, or that cap raised for the pack with the
owner's agreement.

## Render budget (ART_BIBLE §10)

One `DirectionalLight3D`, no GI, no post — unchanged; a Meshy prop is one draw call and one
512² texture. Kitchen item row went 1,660 → 3,830 triangles with the apple and banana swapped
(`props_items` shot note); a full kitchen stays under the 30,000 ceiling.
