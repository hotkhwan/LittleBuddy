# `LB_Rig_v1` — the semantic rig contract

**Status:** design, nothing implemented. Written before any credits are spent, so that whatever
skeleton arrives — from Meshy, from Blender, or from a commissioned artist — is adapted to *this*
rather than the game being rewritten around *it*.

---

## 1. The correction this document exists to make

Earlier notes in this project said "rig to `LB_Rig_v1`", as though we would hand Meshy our bone
names. **We cannot.** Auto-rig produces whatever skeleton it produces, with its own naming.

So `LB_Rig_v1` is **not a skeleton**. It is a **semantic contract the game talks to**, and every
real skeleton is adapted onto it:

```
Meshy skeleton (unknown bone names)
        │
        ▼
   RigProfile          ← the ONLY place a real bone name ever appears
   (bone-name map)
        │
        ▼
   LB_Rig_v1           ← sockets + actions, the game's vocabulary
        │
        ▼
   gameplay            ← never sees a bone name, ever
```

This is the same discipline that already protects the project elsewhere: the domain layer holds
zero 3D types, content addresses the world by semantic id (`kitchen.fridge`), and
`test_architecture_guard.gd` fails the build if either is broken. A bone name leaking into mission
code is the same class of mistake as a `NodePath` leaking into content JSON.

## 2. Sockets

Eight named attachment points. Gameplay asks for these by name and never for a bone.

| Socket | What attaches / aims there | Used by |
|---|---|---|
| `head` | hats, look-at target | dressing, camera focus |
| `mouth` | bottle, cup, spoon, food | **feeding — the Chapter 2 core loop** |
| `leftHand` / `rightHand` | held props | pickUp, give |
| `chest` | bib, badge, hug centre | dressing |
| `hugTarget` | where a teddy is brought to | hugging |
| `itemHoldLeft` / `itemHoldRight` | carried objects | carry, tidy-up |

**Today these come from a hidden procedural proxy.** The Meshy baby has no skeleton, so
`BabyView3D` is kept in the scene, invisible, purely to supply `mouth` and `hug` positions —
`Marker3D.global_position` is unaffected by visibility. That proxy is a **bridge, not a design**:
the whole point of rigging is to delete it.

### Resolution order

1. A bone named in the `RigProfile` → socket is that bone's transform, optionally with an offset.
2. No suitable bone (e.g. `mouth` — no skeleton has a mouth bone) → a **`Marker3D` parented to the
   mapped bone**, positioned once by hand. This is how `mouth`, `hugTarget` and the item-hold
   points will be authored: parented to `head` and the hands, so they follow the animation for
   free.
3. Neither available → the socket reports **unavailable**. It must not silently fall back to the
   model origin: a bottle that feeds the baby's navel is a worse failure than one that refuses.

## 3. Actions

The eleven the owner named, which are a subset of the seventeen the character API already accepts:

```
idle  walk  wave  sit  eat  drink  cry  happy  hug  sleep  wake
```

`character_action_driver.gd` already resolves a **semantic name → clip name** and degrades safely
when a clip is missing, so clips can land one at a time. The `RigProfile` extends that same table
with the names a given skeleton's clips actually carry — e.g. Meshy's `Walking` → `walk`.

**Nothing in mission or content code may name a clip.** It says `play_action("drink")`. That is
already true and guard-tested; a rig must not become the excuse to break it.

## 4. `RigProfile` — the adapter

One resource per character family. The only file in the project that may contain a real bone name.

```gdscript
{
  "profileId": "meshyBabyV1",
  "skeletonPath": "Armature/Skeleton3D",
  "bones": {                       # LB_Rig_v1 name -> the skeleton's actual bone
    "head": "mixamorig:Head", "chest": "mixamorig:Spine2",
    "leftHand": "mixamorig:LeftHand", "rightHand": "mixamorig:RightHand",
  },
  "socketOffsets": {               # Marker3D children, in bone-local space
    "mouth":        {"bone": "head",      "offset": [0.0, -0.02, 0.06]},
    "hugTarget":    {"bone": "chest",     "offset": [0.0,  0.00, 0.08]},
    "itemHoldLeft": {"bone": "leftHand",  "offset": [0.0,  0.00, 0.02]},
  },
  "clips": {"idle": "Idle", "walk": "Walking"},
  "forwardAxis": "-Z",             # the game's convention; Meshy authors +Z
  "heightMeters": 0.78,
}
```

**`forwardAxis` is load-bearing.** Meshy requires the input model to face **+Z** and the project's
characters face **−Z**; the babies already need a 180° correction, and Chapter 2's `BabyView3D`
faces +Z while everything else faces −Z. That is three conventions in one project, and the profile
is where the disagreement gets resolved once instead of being rediscovered per character.

## 5. Acceptance — a rig is only adopted if all of these hold

1. Imports into Godot 4.7.2 with zero errors and a `Skeleton3D` is present.
2. Every `LB_Rig_v1` socket resolves, or reports unavailable — never silently to the origin.
3. Deformation is acceptable at the shoulders, hips and knees under `walk`.
4. `walk` plays and the feet do not skate — the locomotion clip is already speed-scaled to the
   body's real velocity, so the clip's own stride must be measured and recorded.
5. **Feeding and hugging hit the right places with the procedural proxy removed.** This is the
   test that matters; until it passes, the rig has not replaced anything.
6. Runtime triangles inside budget, one material, ≤ 1024² atlas.
7. Full suite green, ContentValidator 0, iOS export and arm64 build green.
8. Measured on a physical iPhone.

Failing 1–5 means the rig is rejected regardless of what it cost.

## 6. One skeleton, not three

Seated and sleeping must become **animation poses on the shared baby skeleton**, not separate
rigged meshes. Three skeletons means three sets of sockets, three retarget paths and three things
to break; the wrapper's `POSES` table is deliberately shaped so it collapses to a single entry the
day a shared rig exists.
