# Changelog

Versioning starts here, at the owner's instruction. The version of record lives in `VERSION` and
must stay in step with `application/short_version` and `application/version` in
`game/export_presets.cfg` — a test enforces that they agree, because a version that disagrees with
the build it labels is worse than no version at all.

Scheme: `MAJOR.MINOR.PATCH`, bumped on every change we make from now on.
- **PATCH** — fixes, polish, content tuning, anything invisible to the shape of the product.
- **MINOR** — a new system or a new player-visible capability.
- **MAJOR** — reserved; nothing here is 1.0 until a child has played it on a device.

---

## 0.1.0 — 2026-09-19

MINOR, not PATCH: two new player-visible systems (speech feedback, storage and
tidy-up) and the caregiver appearing for the first time.

### Added
- **Speech feedback.** Nine states with a face each -- listening, processing,
  "You said: ...", "Great!", "Try again!", microphone-off, unavailable, error.
  Nothing reads as failure and every unhappy state names the touch fallback.
- **Parent speech diagnostic**, behind the parental gate: 15 rows and a verdict
  that names the ROOT cause, so "is the microphone working?" is answerable on
  the device without a Mac and a UDID.
- **Storage and tidy-up**, as pure domain. Containers declared as data; a toy box
  whose lid visibly swings open; refusals that redirect rather than refuse.
- **Door signs.** Every door now carries a glyph and the room name, colour-coded
  per destination.
- **PinkGirl Buddy on screen** for the first time, at 3,898 triangles and one
  512-square atlas -- inside the art bible budget rather than over it.
- **A new app icon**, rendered from the real characters.

### Changed
- Rooms fill the screen at every aspect ratio: the world got bigger rather than
  the camera getting closer, so nothing is cropped.
- Main menu gained Dress Up and Grown-ups without crowding Play and Free Play.

### Fixed
- A 100x unit error in both character wrappers: Meshy rigs export bones in
  centimetres under a 0.01 armature, so the node chain applied it twice and
  reported a 1.65 m character as 0.0165 m.
- `exclude_filter` would have stripped PinkGirl out of the device build
  entirely. The iOS pack also fell from 24.0 MB to 5.0 MB.
- `meshy_rig.sh` silently overwrote another character's paid-for rigged assets;
  it now requires an output stem and refuses to overwrite.

## 0.0.3 — 2026-09-18

### Added
- **Experimental Little Buddy baby avatar** — the three Meshy baby exports, wrapped as **one
  character in three poses** at `scenes/characters/little_buddy/BabyLittleBuddy.tscn` and
  `scripts/characters/little_buddy/baby_little_buddy.gd`. That script is the **only** file in the
  project that names those GLBs or knows their node layout, and a test enforces it.
- **A semantic pose API.** `set_pose("sleeping" | "sitting" | "standing")` loads that pose's GLB
  the first time it is asked for and hides the others; selecting one pose never pays for the other
  two (together 1,026,952 triangles and ~42 MB). `sitting` is the default because feeding is
  Chapter 2's core loop. This is a design, not a workaround: Chapter 2's baby **deliberately does
  not walk**, so a pose-locked mesh costs this character far less than it costs one that must.
- **A Chapter 2 view-state adapter.** `set_view_state(idle|hungry|drinking|happy|hugging)` and
  `get_view_state_name()` answer exactly as `BabyView3D` does, including its fall back to `idle`
  for an unknown state, so existing callers keep their vocabulary. All five feeding-loop states
  map to `sitting` on purpose — with no rig a pose change is an instantaneous mesh cut, and a baby
  that teleported from seated to standing between `hungry` and `happy` would read as a glitch, not
  as a reaction. `sleeping` and `standing` are addressed by scene context instead.
- **One character size across three poses**, which is the specific trap in this asset set: Meshy
  normalised all three files to the same 1.903-unit box, so scaling each to the same rendered
  height would have left a sitting baby a quarter larger than the standing one. Each pose carries a
  measured `heightFraction` (1.000 / 0.796 / 1.000), cross-checked by two independent methods —
  mesh surface area and head width — and `describe_budget()` reports `characterHeight` derived back
  through the real transform chain so the test asserts it rather than trusting the table.
- Normalisation in the wrapper, derived from the measured AABB: scaled to **0.78 m**
  (`CHARACTER_AGE_STAGES.md` §2, Infant, locked and load-bearing for the nursery camera), lowest
  point at the wrapper's origin, horizontally centred, **yaw 0 faces −Z** like every other
  character. The `sleeping` export is a **supine figure Meshy authored upright** — it is reclined
  onto its back in the wrapper, head toward −X so it lies across the frame the way a baby lies
  along a crib. Found by rendering it; no assertion could have caught it.
- Art-bible §7 material policy applied per pose to a *duplicate* of the imported material:
  `metallic` 1.0 → 0.0, normal map removed, ORM map dropped, `cull_mode` DISABLED → BACK, roughness
  0.9. Three 2048² textures reduce to one at runtime. The GLBs on disk stay byte-identical.
- `get_socket()`, `get_height()`, `get_family()` from `CHARACTER_AGE_STAGES.md` §9.1, honouring
  guarantee 2 (never returns null; a missing socket returns the root).
- `test_baby_avatar.gd` — 13 assertion groups covering the gate, the refusal to fake animation, the
  completing no-op, the pose API and its laziness, the one-character-size rule, normalisation,
  material policy, and that no Meshy filename leaks outside the wrapper. Green **with and without**
  the gitignored exports present.
- `docs/shots/baby_*.png` — all three poses beside the procedural `BabyView3D` at 1334×616 and
  1024×768, a face-to-face comparison, and each pose rendered in the live nursery.

### Notes
- The avatar is **disabled by default** (`BabyLittleBuddy.ENABLED = false`) and `BabyView3D`
  remains the Chapter 2 baby that ships, because validation demonstrably does not pass: **255,458 /
  398,404 / 373,090 triangles** against the §10 budget of 4,000 (64× / 100× / 93×; the Infant is
  capped tighter still at 3,000), three 2048² textures per pose, and **no skin, no skeleton and no
  animation clips** on any of them. The gate is enforced by the test, not by a comment.
- **Nothing fakes animation.** `can_play_action()` asks the model and answers `false` for every
  action; `play_action()` is a timed, completing no-op that still emits `action_started` and
  `action_finished` so no caller can hang. A pose swap is deliberately *not* routed through the
  action vocabulary.
- **Two facing conventions exist in this project and they are opposites.** `toddler_view.gd` and
  `pink_girl_buddy.gd` face −Z at yaw 0; `baby_view_3d.gd` faces **+Z**, and the nursery camera
  looks straight at it. This wrapper follows the character convention (−Z), so dropping it onto
  `baby_room.tscn`'s `BabyView` node at identity would show a child the back of the baby's head
  with nothing to warn them. The yaw a Chapter 2 scene needs is named in the wrapper as
  `CHAPTER_2_YAW_DEG`.
- `get_mouth_position()` / `get_hug_position()` are **deliberately absent**. §9.1 forbids
  hardcoding a socket position and §9.3 maps both onto `get_socket()`; a socket is a node in a
  skeleton, and there is no skeleton. Approximating them from a bounding box would put INTERACT's
  drop zones wherever the next re-export happens to put the head. **This, and not the triangle
  count, is what stops the wrapper being a drop-in.**

---

## 0.0.2 — 2026-09-18

### Added
- **Experimental Big Buddy avatar** (`pinkGirl_v01`) — the player's adult caregiver character —
  behind a wrapper scene at `scenes/characters/buddy/PinkGirlBuddy.tscn` and its script
  `scripts/characters/buddy/pink_girl_buddy.gd`. That script is the **only** file in the project
  that knows the GLB's node layout; a re-export with different node names changes one file.
- Normalisation lives in the wrapper, not in the asset: feet on the floor at the wrapper's origin,
  horizontally centred, scaled to **1.65 m** (art bible §4, Mom), and turned so that **yaw 0 faces
  −Z** like every other character in the project. All of it derived from the measured AABB, so a
  re-export at a different size or pivot still lands correctly.
- Art-bible §7 material policy applied to a *duplicate* of the imported material: `metallic`
  1.0 → 0.0, normal map removed, `cull_mode` DISABLED → BACK, roughness pinned to 0.9. Three
  2048² textures reduce to one at runtime. The GLB on disk is untouched.
- Main-menu preview wiring in `scenes/main/main.tscn`/`main.gd`, behind the flag, with its own
  camera framing so the default title screen is unchanged when the flag is off.
- `VERSION` + this changelog, with `test_version.gd` pinning them to
  `application/short_version` and `application/version` in `game/export_presets.cfg`.
- `test_buddy_avatar.gd` — 12 assertions covering the wrapper's normalisation, its material
  policy, and the validation gate on the flag.

- **Three baby GLBs** copied in as pose variants (`baby_standing_v01`, `baby_sitting_v01`,
  `baby_sleeping_v01`). Named by pose because an unrigged mesh is frozen in the pose it was
  generated in. No wrapper yet — which baby becomes the Chapter 2 child is an open design choice.
- `docs/MESHY_CHARACTER_AUDIT.md`, and provenance rows in `docs/ASSET_MANIFEST.md`.

### Fixed
- **The export was shipping 68 MB of disabled assets.** Gitignoring a file does not stop Godot
  exporting it: the `.pck` had gone from ~2 MB to **82 MB** and the app to 183 MB, against a 40 MB
  budget. `exclude_filter="assets/characters/*"` brings the pck back to **2 MB**.

### Notes
- **No bunny mascot exists.** All three ambiguously-named files are babies, confirmed by rendering
  each one; the only bunny in `~/Downloads` is a 2D PNG. The mascot directory is empty and no
  wrapper was created, rather than mislabel a baby.
- **Raw exports are gitignored**, kept on disk at their authored paths. ~84 MB into a 33 MB repo
  with no git-lfs, for assets that cannot ship without retopology. Adding them later is one
  command; removing them later means rewriting published history, which this project forbids.
  The suite is green and the project loads clean with or without them present.
- **Licence unconfirmed and not invented** — see the audit. It collides with the CC0-only policy.
- The avatar is **disabled by default** (`PinkGirlBuddy.ENABLED = false`) and the procedural
  placeholder remains the Buddy that ships. Requirement 6 of the owner's request — "keep the
  current placeholder Buddy as fallback until validation passes" — is in force because validation
  demonstrably does **not** pass: **619,890 triangles** against the §10 budget of 4,000 (155×),
  a 2048² albedo against a 512² budget, and **no skin, no skeleton and no animation clips**.
  Full asset assessment in `docs/BUDDY_AVATAR_REPORT.md`; rendered evidence in `docs/shots/buddy_*`.
- **Measured in the rendered scene, avatar on:** the bedroom goes from 75 draw calls / 25,480
  primitives to **77 / 102,964**, and the kitchen from 75 / 20,772 to **77 / 98,256**. Draw calls
  stay well inside the 220 ceiling (+2, the mesh and its shadow); triangles land at **3.4× the
  30,000 ceiling**. Godot's importer auto-generates LODs, which is the only reason the figure is
  ~77,000 rather than 619,890 — the asset is over budget even after the engine helps.
- The gate is enforced, not documented: `test_buddy_avatar.gd` fails if `ENABLED` is `true` while
  the asset is over budget or cannot animate.
- **Nothing fakes animation.** `can_play_action()` asks the model and answers `false` for every
  action; `play_action()` is a timed, completing no-op that still emits `action_started` and
  `action_finished`, so no caller can hang. No procedural bob-and-sway was added.
- Speech, save, routing, navigation, iOS signing and device family are untouched.

## 0.0.1 — baseline

The production-candidate vertical slice: "A Day With Little Buddy" — five Chapter 3 levels across
four rooms, tap-to-walk, drag, 17 semantic actions, honest 0–3 stars, save v4, onboarding, Free
Play, vocabulary review. 89 tests, ContentValidator 0, iOS export and arm64 build green. Never run
on a physical device at the time this version was cut.
