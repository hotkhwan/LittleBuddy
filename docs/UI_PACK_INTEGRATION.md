# UI pack v1 — integration report

Branch `wt6/ui`, 2026-09-21. The owner supplied `game/assets/ui/generated_v1/`
(eight 512 px PNG icons, a logo concept, an app-icon concept). This is what was
adopted, what was not, and why — plus the touch-target arithmetic and the
before/after frames. Nothing here was run on a device; every picture is from the
SubViewport shot harnesses (`tests/shots_menu.gd`, `shots_settings.gd`,
`shots_tutor.gd`) at the pixel sizes named.

## The rule (one visual language, two tiers)

The game already had one icon language: flat white SVGs from the Nieobie pack,
tinted ink through `IconGlyph`, on every control. The owner's pack is a
different language — full-colour, soft-shaded "sticker" pictures — and it is
the *same* language as the shipped title logo (`assets/branding/littleDaysLogo_*`),
which is glossy, pastel and 3D-ish. So rather than mixing the two per control,
the split is by **meaning**:

> **Pictures name PLACES a child chooses to go. Glyphs name things to DO.**

* Picture tier (`IconGlyph.Glyph.PICTURE_*`, `assets/ui/icons/pictures/`): the
  three child destination cards on the title screen — Play with Bunny, Free
  Play, Dress Up — and the one picture that means "back to the title": the
  house, on **every** Home button (house HUD, tutor HUD, pause card, break
  cards). The house is the same pink-roofed house the logo shows.
* Glyph tier (unchanged): everything a child operates inside a level (Next,
  Speak, Back, Repeat, Mute, the star counter), Learn with Aliz (no pack
  asset), and every grown-up control (the gear on the title, the gate gear).

The picture tier is drawn by the same component (`IconGlyph`), on the same 86%
optical box as the SVGs, so a picture and a glyph sit at matching weight in
matching buttons. Picture glyphs ignore `tint` (they are already coloured) and
sample with mipmaps (the 256 px source is never drawn at 256).

## Every pack asset

| Pack file | Decision | Where | Why |
|---|---|---|---|
| `ui/play.png` | **Used** | Play with Bunny card (`main.tscn` `PlayIcon`, `PICTURE_PLAY`) | The primary CTA; a badge with a triangle reads "press me to start" without a word. Shown at 116 px inside the 240 px card so the badge is a sticker on the button, not a button inside a button. |
| `ui/free_play.png` | **Used** | Free Play card (`ToysIcon`, `PICTURE_TOYS`) | Toys say "play" to a pre-reader. It also *fixes* a real ambiguity: Free Play and Home both used the same flat house before, so "go in" and "go out" were one picture. Now play = toys, home = house. |
| `ui/dress_up.png` | **Used** | Dress Up card (`DressIcon`, `PICTURE_DRESS`) | Replaces the code-drawn T-shirt; a dress on a hanger is the thing the screen does. Pink on the pink frame still reads because the picture carries its own gold hanger, purple hat and white sparkle. |
| `ui/home.png` | **Used** | Every Home button, via `scenes/main/house_glyph.gd` (now a shim over `PICTURE_HOUSE`): house HUD, tutor HUD, pause card, house break card, tutor break card | `house_glyph.gd` documented itself as a stand-in "until the art pass produces a house icon". This is that icon, and it is the house in the logo. Making the shim draw the picture changed all five Home buttons at once with no call-site edits and keeps the `HouseGlyph` node name the tests pin. |
| `ui/settings.png` | **Not used** | — | The gear has a smiling face and sparkles: it is the most child-attracting icon in the pack, on the two controls a child should be *least* drawn to (title Grown-ups, parental gate). `main.gd` and the palette (`PARENT_CHROME`) make Grown-ups deliberately the quietest thing in the row. The flat gear stays, at 100 px. |
| `ui/back.png` | **Not used** | — | Back is level chrome (tutor End lesson pill, Dress Up, sticker book, session summary, activity picker) — glyph tier by the rule — and every Back in the game is a small arrow beside a word in a pill, where a yellow flower badge has no room and would out-shout the primary control next to it. |
| `ui/music.png` | **Not used** | — | The only music control a child sees is the tutor Mute, and its contract (`tutor_glyphs.gd`) is a speaker whose waves go *off* when muted — never a slash, never an X. The pack note has no off state; a cheerful note that looks identical when muted tells the child nothing changed. Music volume lives in the grown-ups panel (Agent B's file) as a slider with a text label. |
| `ui/star.png` | **Not used** | — | ART_BIBLE §8: stars are "one shared glyph at every size", earned `#FFC73D`, next pulsing `#FFE199`, unearned an outline ghost. A star with a face cannot be tinted to those states and cannot be an outline, so using it in one place would break the one-glyph rule everywhere else (counter, rating, celebration, summary). |
| `branding/logo_concept.png` | **Not used** | — | It is the same lockup as the shipped `littleDaysLogo_1024.png` (compared side by side with `docs/shots/menu_wow_iphone.png` and the after frames), but untrimmed (2172×724 with dead margin) and 983 KB against the shipped, trimmed, 391 KB copy with a byte budget pinned by `test_branding_assets.gd`. Nothing to gain at phone size. |
| `branding/app_icon_CONCEPT_NOT_CANONICAL_BUNNY.png` | **Must not ship** (and cannot) | — | Shows a white rabbit, not Bunny. The whole `generated_v1/` folder is now `.gdignore`d, so it is neither imported nor exported; `test_branding_assets.gd` and `test_ui_chrome.gd` fail if that `.gdignore` disappears. |

### Shipping copies

The four adopted icons were re-boxed (content bounds squared about their
centre, expanded so the art covers 86% of the box — the SVG grid) and Lanczos
downscaled to **256 px** into `game/assets/ui/icons/pictures/`
(`play_badge.png`, `toys.png`, `dress.png`, `house.png`; 344 KB total against the
pack's 4.4 MB). Imports: lossless, `mipmaps/generate=true`,
`detect_3d/compress_to=0`, `size_limit=0`. 256 is enough: the largest on-screen
box is 116 design px, which is 232 px at the iPad Pro's 2× scale.

## Touch targets vs visible icons

Design space is 1366×1024 (`canvas_items` / `expand`). ART_BIBLE §8: 240 px
minimum for a primary child-facing control; secondary chrome ≥ 96 px.

| Control | Target (px) | Visible icon box (px) | Art inside box (86%) | Tier | Notes |
|---|---|---|---|---|---|
| Play with Bunny (title) | 240 × 240 | 116 × 116 | ~100 | picture | was 256 card / 112 glyph; caption 30 pt two lines |
| Free Play (title) | 240 × 240 | 116 × 116 | ~100 | picture | was 256 / 124 |
| Dress Up (title) | 240 × 240 | 116 × 116 | ~100 | picture | was 256 / 124 |
| Grown-ups (title) | 240 × 240 | 100 × 100 | ~86 | glyph | flat gear, deliberately the plainest |
| Learn with Aliz (title) | 240 × 240 | 88 × 88 | ~76 | glyph | unchanged (no pack asset) |
| Home (house HUD) | 104 × 104 disc | 80 × 80 | ~69 | picture | was 72 × 72 flat house; ≥ 96 secondary floor |
| Home (tutor HUD) | 104 × 104 disc | 80 × 80 | ~69 | picture | same as above |
| Home (pause card) | 400 × 96 | 60 × 60 | ~52 | picture | picture left of the word |
| Home (house break card) | ≥ 240 × 84 | 56 × 56 | ~48 | picture | |
| Home (tutor break card) | 250 × 84 | 52 × 52 | ~45 | picture | via the shim; file not edited |
| Gate gear (settings entry) | 84 × 84 | 58% of side ≈ 49 | — | glyph | unchanged, grown-up control |
| Mute (tutor) | 120 × 120 (+30 caption) | 76 × 76 | — | glyph | unchanged |
| Back / End lesson (tutor) | 190 × 66 pill | 36 × 38 | — | glyph | unchanged |
| Star counter (house HUD) | not a control | text glyph | — | — | unchanged |

The title row moved from four 256 px cards at 40 px gaps (row top at 1024−292)
to four 240 px cards at 40 px gaps (row top at 1024−276): the same centring,
16 px more garden under the characters' feet, and the targets sit exactly on
the floor rather than 6% above it. `test_menu_wow.gd::BUTTON_ROW_TOP` follows.

## Before / after

All under `docs/shots/`, same harness and pixel size before and after.

| Screen | Size | Before | After |
|---|---|---|---|
| Title | 1334×750 | `uipack_before_menu_ipad.png` | `uipack_after_menu_ipad.png` |
| Title | 2340×1080 | `uipack_before_menu_iphone.png` | `uipack_after_menu_iphone.png` |
| Title | 1366×1024 | `uipack_before_menu_ipad_pro.png` | `uipack_after_menu_ipad_pro.png` |
| House HUD (Home, top-right) | 1334×750 | `uipack_before_house_hud_ipad.png` | `uipack_after_house_hud_ipad.png` |
| House HUD | 2340×1080 | `uipack_before_house_hud_iphone.png` | `uipack_after_house_hud_iphone.png` |
| Tutor HUD (Home, top-right) | 1334×750 | `uipack_before_tutor_ipad.png` | `uipack_after_tutor_ipad.png` |
| Tutor HUD | 2340×1080 | `uipack_before_tutor_iphone.png` | `uipack_after_tutor_iphone.png` |
| Settings gate card | 1334×750 | `uipack_before_settings_gate_ipad.png` | `uipack_after_settings_gate_ipad.png` (byte-identical: no change by design) |
| Settings panel | 2340×1080 | `uipack_before_settings_iphone.png` | `uipack_after_settings_iphone.png` (byte-identical) |

What to look for: on the title, three pictures and one plain gear, captions
inside their frames at all three sizes, feet above the row, logo untouched; in
the HUDs, the peach Home disc now carries the logo's house. Keep-out tests
(`test_menu_wow`, `test_tutor_scene::_test_nothing_covers_alizs_face`,
`test_interaction_ux`, `test_hud_narration_cover`, `test_ui_chrome`,
`test_ui_contrast`, `test_branding_assets`, `test_routing`) all pass; only
`test_menu_wow.gd`'s row-top constant changed, and `test_ui_chrome.gd` /
`test_branding_assets.gd` gained guards (pictures ≤ 256 px, alpha, mipmaps,
never 3D-compressed; picture glyphs ignore tint; `generated_v1/` stays ignored).

## Files touched

* `game/assets/ui/icons/pictures/*` (new), `game/assets/ui/generated_v1/.gdignore`
  (new), `game/assets/ui/generated_v1/README.md` (status note appended)
* `game/scripts/progression/icon_glyph.gd` — picture tier
* `game/scenes/main/house_glyph.gd` — shim over the house picture (announced:
  shared by `house_hud.gd`, `tutor_hud.gd`, `pause_menu.gd`, `break_card.gd`,
  `tutor_break_card.gd`; none of them needed an edit)
* `game/scenes/main/main.tscn` — icon slots and row geometry only; `main.gd`
  unchanged
* `game/scripts/gameplay/house_hud.gd`, `game/scripts/tutor/ui/tutor_hud.gd` —
  Home picture box 72 → 80 px, nothing else
* `game/tests/cases/test_menu_wow.gd`, `test_ui_chrome.gd`, `test_branding_assets.gd`

Now unreferenced and left in place for their owners: `scripts/menu/dress_glyph.gd`
(no longer in `main.tscn`). `house_glyph.gd`'s `tint` / `face_color` /
`window_color` are accepted and ignored so no caller breaks.

## Follow-ups (not done, out of scope or someone else's file)

* The house HUD star counter is a text "★" rather than the shared star glyph;
  worth swapping to `IconGlyph.STAR` + count in a later pass.
* If the owner wants a Learn with Aliz picture, the pack needs a book/lesson
  asset in the same style; the flat book stays until then.
* The stale comment in `main.tscn` describing Learn with Aliz as a 700×96
  banner predates its 240×240 square; harmless, not a rendering issue.
