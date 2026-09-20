# Aliz — face, moods, blink, idle, hair (2026-09-20, evening)

**Zero Meshy credits (balance 3184 before and after). No Blender. Mesh untouched: 3,889
triangles, one 512² atlas, same bounding box.** Follows `ALIZ_POLISH_PASS.md`. Commits
`b88940d` and the checkpoint after it on `wt2/chars`.

Design targets: `game/assets/uiGenerated/branding/appIconSource.png`, `littleDaysLogo.png`.

| Evidence | File |
|---|---|
| Real main menu, before / after, face at 1:1 and 4x | `docs/shots/aliz_face_menu_1x.png` (from `aliz_face_before_menu.png` / `aliz_face_after_menu.png`) |
| Gameplay distance (bedroom framing, house light), 1:1 and 4x | `docs/shots/aliz_face_front_1x.png` (from `aliz_face_before_front.png` / `aliz_face_after_front.png`; `_threeq`, `_back` alongside) |
| Every mood + the blink frame, in engine: close-up / far 1:1 / far 3x | `docs/shots/aliz_moods_sheet.png` (cells in `aliz_mood_<mood>_{close,far}.png`) |
| Idle, three frames 1.5 s apart | `docs/shots/aliz_idle_0.png`, `_1`, `_2` — numbers in §3 |

## 1. The base face — `tools/aliz_face_pass.py`

Measured first with a new instrument, `tools/aliz_ortho_face.py`: a head-on orthographic
render at **1 px = 1 mm of model**, so a feature read off the picture can be typed straight
into a painter that works in metres. It found the iris centres at (±0.100, 1.305), radii
0.039 × 0.048, one 19 × 16 mm highlight per eye, lashes (52, 31, 31), a flat skin of
(253, 206, 182), and **no brows at all** — the generator left them under the fringe.

What changed, all through the same guarded 3D → texel claim map the smile repaint used:

* **Skin** +6 G / −3 B on every skin-family texel of the atlas (62,657 texels): warmer,
  not lighter, body and face together. Icon forehead is (253, 212, 180); ours is now
  (253, 212, 179).
* **Eye highlights** ×1.3 and pure white, plus a second small catchlight low on the far
  side of each pupil (the icon has two).
* **Blush** the old pink pulled halfway back to skin, then a wider, lower, softer oval in
  the icon's rose (252, 176, 166) at 50 % peak, feathered over the outer half.
* **Brows** a soft rose-brown arch (212, 116, 128) 8 mm above each lash line, kind
  (arched, not angled), written only onto skin texels so the fringe above is untouched.
  They sit right at the fringe edge; at gameplay distance they read as a soft shadow of a
  brow, which is the intent.
* **Smile** 84 × 6.2 mm in #B85E5C → **92 × 10 mm in (206, 104, 100)**, corners up 9 mm,
  still closed. The mouth geometry is not touched and the cavity is not reopened.

Judged at 1:1 (`aliz_face_menu_1x.png`, `aliz_face_front_1x.png`): brighter eyes, softer
cheeks, a warmer mouth. **Residue, unchanged from the polish pass:** the right corner of
the smile carries a small upward streak at menu size. The whole mouth is 44 texels across
three islands, two of which are slivers of 7 and 2 texels on a folded triangle; mip
filtering smears them. It is the same streak the previous pass photographed and it needs
the single-layer mouth re-triangulation that pass already named. Not fixable by paint.

## 2. Moods and the blink — `buddy_face.gd`

Bunny's route (repaint the eye/mouth rectangles at runtime) is closed to Aliz: her mouth is
spread over three atlas islands and her eyes over four. So the moods are painted **offline
in model metres** by the same tool, diffed against the new base, and shipped as four RGBA
patches (1–5 KB each, alpha 255 only where a mood differs) plus a manifest
(`pinkGirlBuddy_v01_faces.json`). At runtime `buddy_face.gd` checks six probe texels of
the atlas (a re-export fails them and the whole system stands down), keeps one working
copy of the albedo, and on a change copies the base and `blend_rect`s the active layers.

| mood | layers | what it is |
|---|---|---|
| `content` | — | the base |
| `happy` | mouthOpen | the icon's open smile: cream teeth along the top, tongue low, lip rim |
| `surprised` | mouthO + browsUp | a small round mouth, brows lifted 8 mm |
| `sleepy` | eyesClosed | eyes shut on a relaxed ∪ lid with a lash flick, brows and blush redrawn over the erased sockets |
| *(blink)* | eyesClosed for 120 ms | over any mood; paused while the mood already shuts the eyes |

API on `pink_girl_buddy.gd` (documented at the top of that file): `set_face`, `get_face`,
`get_shown_face`, `available_faces`, `has_face_moods`, `set_blinking`,
`is_blinking_enabled`, `are_eyes_closed`, `blink_now`. Actions wear a face
(`ACTION_FACES`: celebrate/clap/wave/hug/give → happy, wake → surprised, sleep → sleepy)
and hand the resting face back when they end. The blink is a one-shot `Timer` under the
wrapper's `Model` node, 120 ms shut every 3–6 s randomised — no `_process`, so
`test_buddy_avatar.gd`'s scan still holds.

## 3. Idle and hair

**Idle** — `buddy_life_clips.gd`, an authored `Animation` on her real skeleton, merged into
the player's library the way Bunny's are (an animator's `idle` would win). 7.6 s loop: two
breaths across the three spine bones, a **±0.6° head bob**, and a **weight shift every
3.8 s** — hips tilt 2° over one foot and the thighs counter-tilt so the feet stay planted.
`play_action("idle")` resolves through the ordinary driver, and `set_locomotion(0)` now
hands a walk/run over to it instead of stopping the player on its last frame.

Bone deltas from rest, printed by `test_aliz_life.gd` on the real skeleton (bone units are
centimetres):

```
t=0.3s  head (+1.03, -0.12, +0.49) cm  head 0.50°  spine 0.30°  hips 1.53°
t=1.8s  head (+1.25, +0.08, -0.70) cm  head 0.60°  spine 0.96°  hips 2.00°
t=3.3s  head (+1.27, -0.13, +0.51) cm  head 0.48°  spine 0.94°  hips 2.12°
t=4.8s  head (-1.28, +0.07, -0.29) cm  head 0.20°  spine 0.64°  hips 2.00°
```

The head crosses from +1.3 cm to −1.3 cm as the weight changes foot; cubic hold keys were
added after the first version overshot a 1.5° key to 3.7°.

**Hair** — the rig has no hair bones (24 bones, `Head` → `head_end`/`headfront`), so this is
the vertex-free trick: `buddy_hair_sway.gd`, a `SkeletonModifier3D` on the head bone,
**±0.4° tilt at 2.7 s and ±0.25° turn at 4.1 s**, layered on the current pose so it rides
the idle and the walk alike. At ±1° the face visibly wobbled; ±0.4° is the number.

## 4. Contact hint

`scripts/characters/contact_shadow.gd`: there were no fake blob shadows to remove
(neither light casts), and without anything under her she read as a centimetre off the
floor. A 0.22 m soft dark-peach ellipse at alpha 0.18 under her feet — centred on the
feet, not the origin, because her hair and dress reach further than her shoes — lifted
25 mm so the house rugs (18–20 mm plates) do not hide it. A hint, not a blob.

## 5. Tests and gates

`test_aliz_life.gd` (new, 6 groups): idle exists, loops, moves the head between 0.15 and
6 cm, no bone past 6°, the hips lean both ways; `set_locomotion(0)` returns to the idle and
does not restart it every frame; every mood changes texels only inside its layers' rects
and `content` restores the atlas to the pixel; the blink shuts and reopens, is paused by
`sleepy`, and `set_blinking(false)` reopens; a held action's face hands back on release;
the hair sway is on the head bone only, peaks between 0.2° and 0.6°, two periods.
`test_buddy_avatar.gd` and `test_aliz_face.gd` unchanged and green (the blink `Timer`
lives under `Model` so the sealed-hierarchy rule holds). Suite: 129 cases, 0 failures;
both mission smokes PASS.

## 6. Tools

| Tool | Purpose |
|---|---|
| `tools/aliz_ortho_face.py` | 1 px = 1 mm head-on render; `find_features()` measures irises, highlights, lashes |
| `tools/aliz_face_pass.py` | the base pass and the four mood layers + manifest |
| `tools/aliz_face_sheet.py` | atlas-side contact sheet of the moods (composited exactly as the runtime does) |
| `tools/aliz_shots.gd` | in-engine: `views`, `mood`, `idle` jobs |
| `tools/aliz_face_strip.py` | tiles the in-engine mood shots |

Restoring: `git checkout 238501c -- game/assets/characters/buddy/pinkGirl/` then
`Godot --headless --path game --import`; the face system stands down by itself on the old
atlas (its probes fail) and nothing else changes.
