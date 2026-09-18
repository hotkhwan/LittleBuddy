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
