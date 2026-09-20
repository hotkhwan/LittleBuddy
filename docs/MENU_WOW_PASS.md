# Menu WOW pass — 2026-09-20

Owner feedback on the real build: the title screen was a green plane under a
blue sky and did not feel like a children's game world.

## What changed

- **A storybook garden**, built in code from built-in primitives only
  (`game/scripts/menu/menu_garden.gd`, `Garden` node in `main.tscn`): a pastel
  cottage with a cream skirt and eave, terracotta-pastel gabled roof, chimney,
  two mullioned windows with flower boxes, a round attic window and a bright
  sunny arched **front door** with a step and mat; a stepping-stone path from
  the door to the camera; four flowerbeds; seven round trees with fruit; a
  picket fence; soft rolling hills; a gradient pastel sky dome; four clouds;
  a sun; toy balls, a duck and a mailbox. Every colour is a `palette.gd`
  token or one of its two derivations (`light()` / `deep()`); no black, no red.
- **The real cast**: Aliz (`PinkGirlBuddy.tscn`) at the centre, **Bunny**
  (`BabyLittleBuddy.tscn`, the same wrapper the house uses; added in
  `main.gd::_add_bunny()`, playing his `idle`) at her right, Little Buddy
  (`toddler_view.gd`, still pinned by `test_buddy_avatar.gd`) at her left. New
  framing `CAMERA_POSITION_WITH_BUDDY` / `CAMERA_TARGET_WITH_BUDDY`: 10° pitch,
  feet above the button row, heads below the title, sun on their faces.
- **Four buttons in one row** (`main.tscn`): Start/Continue (mint, play glyph),
  Free Play (peach, house), Dress Up (pink, new shirt-with-heart
  `dress_glyph.gd`), Grown-ups (lavender, gear). 256×256 each, 40 px gaps,
  centred, 38 pt captions. `main.gd` adds a soft `StyleBoxFlat` drop shadow
  behind each and a squish-to-92% + `gentle_tap` on press. Start/Continue
  logic, routing and first-run behaviour are unchanged.
- Budget: one `DirectionalLight3D`, shadows off, no other lights, no
  post-processing, garden ≈ 36k triangles (cap 40k in the test), every garden
  mesh `cast_shadow = OFF`.

## Evidence

Rendered through `game/tests/shots_menu.gd` (SubViewport at the exact pixel
size with `size_2d_override` so the UI scales exactly as `Window` does on a
device; PNG size asserted):

| Shot | Size | Verdict |
| --- | --- | --- |
| `docs/shots/menu_wow_ipad.png` | 1334×750 | PASS — house, garden, all three characters clear of the buttons |
| `docs/shots/menu_wow_iphone.png` | 2340×1080 | PASS — same, wider garden, buttons inside the safe area |
| `docs/shots/menu_wow_pressed.png` | 1334×750 | PASS — Start held down, visibly squished |

## Checks

| Item | Result |
| --- | --- |
| `run_tests.gd` | **PASS — 123 case(s)** (was 122; `test_menu_wow.gd` added, nothing weakened) |
| Buttons open their scenes (real `pressed` → real `_enter_scene`) | PASS (`test_menu_wow.gd::_test_each_button_opens_its_scene`) |
| Palette / black / red scans, UI layout, lighting, buddy-avatar guards | PASS (existing cases) |

## Known limits

- The title panel hides the roof peak and chimney; the house reads fine
  without them.
- Aliz has no idle clip (only walk/run ship), so she stands still; Bunny idles.
- Little Buddy (procedural toddler) stays on screen because
  `test_buddy_avatar.gd::_test_little_buddy_is_untouched` pins him in
  `main.tscn`; dropping him to a two-character menu is a one-line change in
  `main.tscn` plus that test.
