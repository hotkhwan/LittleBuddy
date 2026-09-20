# Menu home pass -- 2026-09-20 (Agent B, branch `wt2/home`)

What changed on the title screen, and where the proof is.

## Garden (`game/scripts/menu/menu_garden.gd`)
Layered trees in three leaf tints, a hero tree front-left with a hanging
"Welcome!" sign, two blossom trees, a hedge behind the picket fence, seven
flowerbeds of round-petalled flowers (pink / yellow / white) plus buds, a stump
with a sleeping cat, three butterflies, a bluebird on a warm pink mailbox with a
cream heart, Bunny's teddy and a striped ball, far cottages on the hills, six
clouds, corner bushes, a rose-pink roof, a heart on the door, flower boxes
under the windows. 53,966 triangles (cap 60k in `test_menu_wow.gd`), one
`DirectionalLight3D`, shadows off, no post-processing.

## Ambient motion (`tick(delta)` in the garden)
Canopies, flower heads, bushes and the sign sway 2-3 degrees on a slow sine
with per-instance phase; clouds drift and wrap; butterflies fly a figure-eight
and flap; the cat breathes. Bunny plays his `idle` clip; Aliz plays `idle`
through `play_action()` only when `can_play_action("idle")` says the clip
exists (Agent E is authoring it).

## The walk home (`game/scripts/menu/menu_departure.gd`)
Start / Free Play: buttons fade, Aliz turns and steps to Bunny (0.35 s), lifts
him into the real carry -- `carryFront` socket + carry arm pose + Bunny's
`carried` clip (0.45 s) -- both head up the path while the camera follows, the
door swings open at 1.6 s, a cream cover comes up from 2.1 s, and at 2.5 s
`main.gd` runs the same routing it always did (Start/Continue, first run,
fallbacks untouched). A tap anywhere skips straight to the hand-off. The cover
lives under the tree root so it survives the swap and reveals the new scene.
Hooks for `scripts/branding/scene_transition.gd` (cover/reveal) and
`scripts/branding/logo_title.gd` (replaces the text title panel) are behind
`ResourceLoader.exists()` guards.

## Dress Up (`game/scenes/dress_up/dress_up.tscn`, `scripts/menu/dress_up_screen.gd`)
Real Aliz on a pastel stage, four big swatches (pink, mint, lavender, sunny)
that recolour a hair bow, a tutu frill and shoe bows pinned to her sockets (her
mesh is one atlas surface, so the dress itself cannot be tinted alone), "More
outfits soon!", big Back. Back returns to `main.tscn`. The chosen swatch is
remembered in `settings.dressUpTint` only when a swatch is pressed.

## Version
`v` + `GameVersion.BUILD`, bottom-right, 15 px, ink at 55%. The only place.

## Evidence
- `docs/shots/menu_wow_ipad.png` (1334x750), `docs/shots/menu_wow_iphone.png` (2340x1080)
- `docs/shots/menu_depart_walk.png` (0.30 s), `menu_depart_carry.png` (0.68 s),
  `menu_depart_door.png` (2.05 s) -- hand-stepped; `menu_depart_live.png`
  (2.25 s, driven by `_process`)
- `docs/shots/dress_up_mint.png` -- mint swatch applied
- Headless: `test_menu_wow` (garden, budget, framing, buttons route, ambient
  motion, departure completes inside 2.5 s and skips on a tap, version label,
  Dress Up round trip). Suite: 128 cases, 0 failures.

Regenerate: `Godot --path game --script res://tests/shots_menu.gd -- <name> <WxH> [pressed|depart <s>|departlive <s>|dressup <swatch>]`.
