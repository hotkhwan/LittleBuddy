# Bunny — richer emotions, readable at gameplay distance (2026-09-20, evening)

**Zero Meshy credits. Shipping rig and atlas untouched on disk; every face is a runtime
repaint and every motion a keyframe on the real skeleton.** Follows
`BUNNY_EXPRESSION_PASS.md`.

| Evidence | File |
|---|---|
| Every mood + blink on the real model at the feeding-portrait distance: close-up / far 1:1 / far 2x | `docs/shots/bunny_moods_sheet.png` (cells `bunny_<cell>_{close,far}.png`) |
| The moods on the atlas itself, all three eye charts | `docs/shots/bunny_moods_atlas.png` |
| Neck, five angles at 22° FOV | `docs/shots/bunny_neck_before.png` |
| The real feeding portrait, before / after this pass, neck at 3x | `docs/shots/e_neck_feed.png`, `e_neck_after_feed.png`, `bunny_neck_feed_before_3x.png`, `bunny_neck_feed_after_3x.png` |

## 1. Three new faces and a blink — `baby_face_moods.gd`

| mood | eyes | brows | mouth | cheeks | when (`child_life.gd`) |
|---|---|---|---|---|---|
| `hungry` | the exported eyes, big and asking | inner ends **up** (pleading) | a small pout with a catchlight | — | `fuss` for HUNGRY or THIRSTY |
| `sleepy` | **half-lidded** — the top half filled to a heavy lid, the lower half still looking | — | — | — | `idle` while the need is SLEEPY; the idle also plays at 0.72× |
| `hmph` | open | inner ends **down** | a short flat line | **puffed**: a deeper rose over each cheek | a need ignored past 12 s; the `stamp` clip |
| *(blink)* | shut on a near-straight lid | kept | kept | kept | 120 ms every 3–6 s, over any mood whose eyes are open |

Three brow boxes and three cheek boxes were measured on the atlas the same way the eyes
were (the head is unwrapped twice; the character's left eye, brow and cheek exist in two
charts). `paint(base, mood, closed_eyes)` paints the mood and then, if asked, shuts the
eyes — so a blink over the pout keeps the pout. `delighted` and `asleep` already have the
eyes shut and are returned unchanged. The wrapper exposes `set_eyes_closed()` /
`are_eyes_closed()`; the clock lives in `child_actor.gd::live()` because the wrapper may
not run a frame loop (`test_baby_avatar.gd`).

Design note: `hmph` is the cute-frustrated face the brief asked for. It has no teeth, no
tears and no scowl; the words the face file may not use in executable code (`angry`,
`cross`, `score`, `percent`…) are still scanned by `test_bunny_face.gd`.

## 2. Urgency escalates on three channels at once — `child_actor.gd`, `child_life.gd`, `child_needs.gd`

A need that is uncomfortable (hungry, thirsty, needs comfort, crying) and left alone —
Bunny standing about, not carried, not being cared for, not in his happy window — runs an
escalation clock. At **`IGNORED_AFTER_SEC` = 12 s**:

* the bubble switches to the need's **urgent line** (`child_needs.gd::LINES_URGENT`, e.g.
  "Aliz! I'm SO hungry!"; Mission 01's opener "I'm hungry, Aliz!" is unchanged as the first
  line);
* the face goes to **`hmph`**;
* the body plays **`stamp`** once — a new 0.9 s one-shot in `baby_life_clips.gd`: right
  knee up, foot down, the whole child dips and bounces, arms straight and a little back with
  balled hands, chin up and head turned away — and returns to `fuss`; another stamp every
  **`STAMP_EVERY_SEC` = 6 s** while it goes on.

The clock resets the moment the need changes, the child is fed (`satisfy`), picked up, or an
activity starts. It is a request getting louder, not a timer running out: nothing is lost
and nothing counts down (`CLAUDE.md`, Child UX). Verified end to end through the real actor
in `test_bunny_face.gd::_test_urgency_is_readable()`.

Face and body still come from one decision: `face_for(clip, need, ignored_for)` refines the
face *within* the clip (`fuss` → `hungry` / `unhappy` / `hmph`; `idle` → `sleepy` /
`content`) and can never put a smile over a fuss. Called with the clip alone it is the
original mapping, so every older assertion still holds.

Read at the feeding distance (`bunny_moods_sheet.png`, middle row, 1:1): the pout and
pleading brows, the half-lids, the puffed cheeks with the flat mouth and the turned-away
stamp all read as different states of one child at ~230 px tall.

## 3. The neck — inspected, nothing to fix

`babyLittleBuddy_v01.glb`: 14,406 triangles, **0 boundary edges** after welding (a closed
shell), **0 welded vertices with split normals over 25°**, no dark texel on the front of the
neck band (y 0.80–1.04 of 1.70, z > 0), no dark gutter texel grazing it. Five 22° FOV
renders from front, three-quarter, side, back and the other three-quarter
(`bunny_neck_before.png`) show a clean chin-to-collar transition with no ring, gap or
normal step. The real feeding portrait at 3x (`bunny_neck_feed_before_3x.png` /
`bunny_neck_feed_after_3x.png`) shows the same. The only marks near the jaw in that frame are
the fist's finger creases from the drink pose. Nothing was changed; triangle count and
atlas stay as they were.

## 4. Contact hint under his feet

`scripts/characters/contact_shadow.gd`, radius 0.15 m for him (0.22 m for Aliz), alpha
0.18, dark peach, centred under the feet (his head reaches further forward than his toes,
so the origin is not the stance), 25 mm up so the rugs do not hide it. In the feeding
portrait the mat under his shoes goes from (197, 197, 186) to (185, 182, 171): a hint.
There were no fake blob shadows anywhere to remove.

## 5. Tests

`test_bunny_face.gd` extended (not weakened): seven moods in both vocabularies; the
clip → face table with the need refinements and the sleepy pace; brows and mouth repainted
and nothing outside the ten feature boxes for `hungry` and `hmph`; the pout keeps the
exported eyes; the blink shuts every eye box, leaves the mouth alone, and is a no-op over
`asleep`; through the real actor a hungry fuss pouts and a comfort fuss stays unhappy;
urgency escalates line + face + stamp at 12 s and not before, resets on feeding and on
being carried; the blink cadence through `live()`. One old expectation changed on purpose:
a hungry fuss now wears `hungry` rather than `unhappy` — that is the brief. `test_bunny_life`,
`test_child_needs`, `test_baby_avatar`, `test_carry_bunny` unchanged and green. Suite: 129
cases, 0 failures; both mission smokes PASS.

## 6. Tools

| Tool | Purpose |
|---|---|
| `tools/bunny_shots.gd` | every mood + clip cell on the real model, feeding distance and close-up, deterministic |
| `tools/bunny_face_strip.py` | tiles them |

## 7. Not done

* The stamp is one of the two kinds of thing the brief allows for an ignored need; a
  looping "tantrum" was deliberately not authored.
* `crying` still shares `fuss` with the other needs (playback rate apart), as before.
* Nothing here has been seen on a physical device.
