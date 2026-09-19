# HUD presentation pass — the P0 close-up defect

**Branch:** `feature/overnight-production-candidate` · **Engine:** Godot 4.7.2 · **Not committed.**

The sprint's P0: during a close-up the HUD's text stack sat on the character's face. The previous
camera pass (`docs/WORLD_CAMERA_PASS.md` §7.1) established — correctly — that this cannot be fixed
from the camera, because `camera_framing.solve()` always aims at screen centre, so widening the
chrome inset only pushes the camera back and carries the overlap with it. **The text had to move.**

Every picture below is a render of the real `scenes/house/house_world.tscn`, driven by the real
`house_level_director.gd` through a real mission, at the two resolutions the brief names, and
**every one of the sixteen was opened and looked at**.

---

## 1. What was actually on screen

`docs/shots/hud_feed_BEFORE_ipad.png` — `snackTime`, the `feedBunnySnack` beat, 1334×750:

| line | owner | y (of 750) |
|---|---|---|
| "Give Bunny the food." | `house_hud` prompt | 132–232 |
| "ให้น้องกินขนม" | `house_hud` Thai hint | 236–288 |
| "Let's get Bunny some food first!" | `house_hud` assist | 300–380 |

248 px of text down the centre column — **33% of the screen's height** — with the beat putting Aliz
dead centre and Bunny just below her. Her eyes are behind the Thai hint and the assist line runs
across her mouth. It is the first thing the eye lands on and it is in every tight close-up in both
shipped missions.

### A second overlay was in the evidence, and it was not the HUD

`c_beat_counter_ipad.png` — the picture the P0 was raised from — also contains **"Tap the floor. I
will walk!"** and a pointing hand. Those belong to `onboarding_director.gd`, not to the HUD, and
**the real game never shows them at the same time as a mission**: `house_world._ready()` is
`if _begin_onboarding(): return`. The harness force-starts a level, so on a fresh profile it got
both at once and filed the result as evidence about the HUD.

`shot_harness.gd`'s `beat` job now ends the tour first, and says so. Every `BEFORE` shot here is
therefore a *harder* test of the HUD than the original evidence: the defect is entirely the HUD's,
with nothing else to blame.

---

## 2. The rule: the HUD watches the shot

Four presentation modes, and **nothing new is asked of the director**. The HUD reads one number off
the camera that is already rendering it — `RoomCamera.get_focus_radius()`, the half-width of the
square `camera_focus.gd` composed — and that number already says which kind of shot this is.
Measured by rendering both shipped missions:

| beat | kind | radius |
|---|---|---|
| `walkToBathroom` | `travel` | no close-up |
| `wakeUpBuddy`, `sayGoodMorning` | `choose` | **1.88 m** |
| `bananaOnCounter`, `mashTheBanana`, `carrySnackToBunny`, `feedBunnySnack` | `goAndDo` | **0.90 m** |

The two classes are a metre apart and nothing lands in between, so one threshold separates them.
`WIDE_SHOT_RADIUS = 1.30` sits in the middle of the gap with 0.40 m of margin either side, and
`test_hud_presentation.gd` fails if it ever stops doing so.

| mode | entered when | layout |
|---|---|---|
| **EXPLORE** | no close-up | prompt 42 pt + Thai 27 pt top-centre, as shipped. The assist line moves to a band above the buttons. |
| **PREPARE** | close-up ≥ 1.30 m (a row of objects to choose from) | the same column, compacted: prompt 34 pt at y 90, Thai 27 pt at y 150. Stack 248 px → **102 px**. |
| **FEED** | close-up < 1.30 m (one subject filling the middle) | the text leaves the centre entirely: a **left rail** under the stars and the progress dots, 30 pt, left aligned, ink on a cream outline. Thai hint stands down. |
| **COMPLETE** | a task was just marked done | not a position but a subject: the finished instruction and its hint go, the star count grows to 42 pt, and the praise has the bottom band to itself. |

`COMPLETE` borrows whatever mode it interrupted and lasts `REWARD_SECONDS` (1.8 s) — or less, see §4.

### Why the left rail, and why ink

The left margin is the only part of the frame a tight close-up never uses. Measured off
`hud_feed_AFTER_ipad.png`: the two characters span x = 0.42 … 0.59 of the width. The rail's right
edge is at 0.33, and the test asserts it never enters the central fifth at any of the three aspects.

It is set in **`ink` with a cream outline** — the inverse of every other line in this HUD, and the
same inversion the Free Play word card already uses for the same reason. Cream-on-cream with a thin
ink edge was rendered first and was legible-but-weak: in a close-up the left margin is a pale cream
wall almost every time. `#000000` appears nowhere; `ink` is the palette's only dark.

### Why the assist line moved in *every* mode

It was a fourth line in the same column and it is the one line that is always short, always
transient, and never the thing the child is being asked to look at. It now sits in a band above the
button row in all four modes. The band is asserted not to intersect `house_hud.button_rects()` at
any aspect, so it can never come to rest across **Next** — the escape hatch `CLAUDE.md` requires.

---

## 3. Evidence

All in `docs/shots/`, rendered from the real house, both resolutions, all sixteen looked at.

| file | beat | mode the HUD chose |
|---|---|---|
| `hud_explore_{BEFORE,AFTER}_{ipad,iphone}.png` | `goodMorningRoutine` / `walkToBathroom` | EXPLORE |
| `hud_prepare_{BEFORE,AFTER}_{ipad,iphone}.png` | `goodMorningRoutine` / `wakeUpBuddy` (1.88 m) | PREPARE |
| `hud_feed_{BEFORE,AFTER}_{ipad,iphone}.png` | `snackTime` / `feedBunnySnack` (0.90 m) | **FEED** |
| `hud_complete_{BEFORE,AFTER}_{ipad,iphone}.png` | the same beat, just completed | COMPLETE |

**Every AFTER shot's mode was chosen by the game, not by the harness.** The harness prints it
(`hudMode=FEED`) alongside the beat and the radius, so the picture carries its own label; a HUD with
no presentation mode, or no room on screen, prints a `WARN` instead of quietly photographing
something else.

Reproduce:

```
Godot --path game --resolution 1334x750  res://scenes/spike/shot_harness.tscn -- beat <out> "snackTime:22"
Godot --path game --resolution 2340x1080 res://scenes/spike/shot_harness.tscn -- beat <out> "snackTime:22:reward"
```

What the AFTER shots show, honestly: in FEED both faces are completely clear at both resolutions and
the instruction reads cleanly against the wall. PREPARE's two lines sit over the wall and the window
where they were previously cut by the hanging mobile. EXPLORE changes least — it was never the
defect — and the only difference is the assist line dropping to the bottom. COMPLETE is the
biggest visual change: at the moment of reward the middle of the screen is completely empty.

---

## 4. What becomes unavailable in each mode, and why that is safe

`CLAUDE.md` forbids dead ends, so each one is argued rather than asserted.

**EXPLORE — nothing is hidden.** The assist line moved; it did not go.

**PREPARE — nothing is hidden.** Prompt 42 → 34 pt and Thai 27 → 27 pt (unchanged). ART_BIBLE §8's
27 pt floor is enforced across all four modes by `_test_no_text_drops_below_the_readable_floor()`.

**FEED — the Thai hint is hidden.** Four reasons it is safe, in order of weight:

1. FEED begins **on arrival at the beat**. Every route to a beat passes through EXPLORE or PREPARE,
   both of which show the hint, so the child has already had it for the whole walk.
2. The English instruction itself stays on screen, and the spoken prompt is untouched — the voice is
   the primary channel for a pre-reader, and nothing about it changed.
3. It returns the instant the close-up ends: the camera releasing, the child walking away, the next
   task. `_test_nothing_is_hidden_without_a_way_back()` asserts the return, and asserts the hint's
   *text* is retained rather than cleared.
4. `house_hud.gd`'s own existing note says an always-on hint is not a hint but a translation. FEED is
   the one moment where the thing being taught is in front of the child's eyes.

**COMPLETE — the finished task's instruction and hint are hidden, for at most 1.8 s.** The task is
done; the instruction for it is the one statement on screen that is certainly no longer true. It
cannot swallow the *next* instruction: `set_prompt()` with different text ends the reward moment
immediately, which is asserted. It also opens on a **skip**, deliberately — COMPLETE shows praise and
a filled dot and never a score, so it cannot congratulate a child for something they did not do, and
`CLAUDE.md` forbids marking a skip as a failure in any case.

---

## 5. Files changed

| file | what |
|---|---|
| `game/scripts/ui/hud_presentation.gd` | **new.** The rule, the four layouts, the measurements. Pure — Dictionaries in, Dictionaries out. |
| `game/scripts/gameplay/house_hud.gd` | applies a mode; watches the camera in `_process`; one `_refresh_visibility()` now owns every label's `visible`. |
| `game/scripts/camera/room_camera.gd` | `get_focus_radius()` — read-only, derived from the live `bounds` so it cannot drift from the shot on screen. |
| `game/scenes/spike/shot_harness.gd` | ends the first-run tour before forcing a level; prints the radius, the room and the HUD mode; new `:reward` suffix for the COMPLETE moment; shorter settle for it. |
| `game/tests/cases/test_hud_presentation.gd` | **new**, 11 checks. |

**A note on ownership.** The brief assigned me `game/scripts/ui/house_hud.gd`. That file does not
exist: the HUD is `game/scripts/gameplay/house_hud.gd`, which the same brief lists under DO NOT
TOUCH. I took the explicit file grant as authoritative over the blanket directory rule (the brief
also says in as many words that the fix "needs `house_hud.gd` to move the assist line") and edited it
in place rather than moving it, because moving it would mean editing `house_level_director.gd`,
`house_freeplay_director.gd` and four test files that I do not own. **No other file under
`scripts/gameplay/` was touched.**

### Tests

`115 case(s), 0 failure(s)`. No existing case was weakened or modified. Both mission smokes pass
(`smoke_mission01.gd`, and with `-- snackTime`). The suite was 113 at the start of this pass; my
case is one of the two added since — another workstream is editing the same tree.

The eleven checks, briefly: the layout table is complete (anti-vacuity) · every measured beat lands
in the right mode from the radius alone · the threshold sits between the two measured classes with
margin · the optional task-kind hook and the radius rule can never disagree · FEED never enters the
central fifth of the width at any of three aspects · the top stack shrinks 288 → 102 → 0 px ·
nothing drops below 27 pt · the assist band never touches Next or Speak · the hint and the prompt
both come back · **`get_focus_radius()` really reports what the HUD reads** (without this the HUD
would sit in EXPLORE for ever with every other check still green) · a HUD with no camera still works.

---

## 6. What I need from you — one line, and it is optional

Nothing is required. The radius derivation matches the task kind on **every beat in both shipped
missions**, which is why this works today with no change to `house_level_director.gd`.

If you would rather the director state it authoritatively — so that a future beat whose shot stops
describing it cannot mislay the HUD — the whole change is one line in `bind()`, after
`_hud.call("build")`:

```gdscript
task_plan_changed.connect(func(_id: String, kind: String) -> void: _hud.call("set_task_kind", kind))
```

`set_task_kind()` already exists on the HUD and `task_plan_changed` is an existing signal;
`test_hud_presentation.gd` asserts the two derivations cannot disagree, so wiring it up cannot move
the layout without something going red.

---

## 7. What is still imperfect

1. **Bunny's need bubble lands on Aliz's chest.** "I'm hungry!" is a `Label3D` on `child_actor.gd`
   (`scripts/care/**`), billboarded above Bunny's head — which in the feeding close-up is directly in
   front of Aliz's torso. Visible in `hud_feed_AFTER_ipad.png`. Not mine, not the HUD, and now the
   most visible text overlap left in that shot.
2. **The onboarding caption's band is unclaimed.** `onboarding_director.gd` owns y 52–156 centre. The
   game never runs it beside a mission so there is no live collision, but the two layouts are
   authored in different files with no shared constant. PREPARE deliberately stops at y 90 and FEED's
   rail starts at y 160 to stay clear of it anyway.
3. **The HUD does not respect the device safe area.** It never did — `scripts/ui/safe_area.gd` exists
   and this file does not use it. The left rail is at x = 36, the same margin the star counter has
   always used, so nothing got worse, but an iPhone notch in landscape is real and this is where it
   will bite.
4. **EXPLORE's improvement is small.** One line moved. The room shot was never the defect, and
   pretending otherwise would have meant changing a layout that is working.
5. **`COMPLETE`'s star emphasis is a font size, not an animation.** ART_BIBLE §8 asks for ease-out
   150–250 ms with slight overshoot on appearance; the star simply changes size. It reads as
   deliberate in the render but it is not what the Bible specifies.
6. **The beat harness is not deterministic.** `skip_current_task` does not always advance one task
   per call, so a `"snackTime:22"` run occasionally lands on a neighbouring beat or fails to tighten.
   It now **prints** the beat, the radius, the room and the mode, so a wrong one is caught rather
   than filed — one explore render did come out as the empty void beyond the rooms and was re-taken —
   but a screenshot run still needs its output read.
7. **Nothing here has run on a physical iPad.** Every picture is a Mac render at the stated
   resolution.
