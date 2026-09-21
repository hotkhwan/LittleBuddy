# Grown-ups / Settings verification (2026-09-21, wt6/settings)

Every row below was driven with REAL pointer events (`Viewport.push_input`) through the
laid-out panel by `game/tests/input_settings_harness.gd`, which prints one
`PROBE <name>: PASS|FAIL` line per scenario. A second finger is pushed exactly as
`Input` delivers it under `emulate_mouse_from_touch=true`: the first finger as an
emulated mouse event followed by its touch, any further finger as a bare
`InputEventScreenTouch` / `InputEventScreenDrag` with its own index and no mouse event.
Persistence rows use the REAL `SaveService` + `ProfileStore` on a scratch file
(`user://input_settings_harness_profile.json`, deleted afterwards); the project's
autoloads are detached for the whole run, so no real profile is ever touched.

**Nothing here is a device claim.** No iPad or Android device was used. Rows marked
NOT TESTABLE HEADLESS say what the owner must check by hand.

How to run:

```
cd game
Godot --headless --path . --script res://tests/input_settings_harness.gd     # INPUT SETTINGS OK
Godot --headless --path . --script res://tests/run_tests.gd                  # the suite (runs the harness as a child)
Godot --path . --script res://tests/shots_settings.gd -- ipad 1334x750       # docs/shots/settings_*_ipad.png
Godot --path . --script res://tests/shots_settings.gd -- iphone 2340x1080    # docs/shots/settings_*_iphone.png
```

## Verbatim results

Harness (`INPUT SETTINGS OK`, exit 0):

```
PROBE footer reachable 1334x750: PASS
PROBE footer reachable 2340x1080: PASS
PROBE scroll from slider: PASS
PROBE scroll from button: PASS
PROBE scroll from text, Close and language button: PASS
PROBE taps still work: PASS
PROBE slider still drags: PASS
PROBE footer and gate card swipes are inert: PASS
PROBE two fingers: PASS
PROBE gear tap and hold: PASS
PROBE close, Escape, Android back: PASS
PROBE home from the pause card: PASS
PROBE home from the title: PASS
PROBE sliders drive the mixer and persist: PASS
PROBE language updates and persists: PASS
PROBE tutor toggles persist and the classroom reads them: PASS
PROBE privacy information is static: PASS
PROBE delete history and reset progress: PASS
PROBE no dead overlay 1334x750: PASS
PROBE no dead overlay 2340x1080: PASS
PROBE no dead overlay 1024x768: PASS

INPUT SETTINGS OK
```

Suite (`run_tests.gd`):

```
PASS - 159 case(s), 0 failure(s)
```

Shots (`shots_settings.gd`): `SETTINGS SHOTS OK` at both sizes; see the Shots section.

## Checklist

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Touch scrolling from a **slider** track (vertical drag scrolls, the volume is put back, the slider is not left grabbed) | AUTOMATED PASS | `PROBE scroll from slider: PASS` |
| 2 | Touch scrolling from an option **button** (scrolls, the button neither fires nor sticks) | AUTOMATED PASS | `PROBE scroll from button: PASS` |
| 3 | Touch scrolling from plain **text**, from the header's **Close**, from a **language button** (scrolls; nothing closes, the language does not change) | AUTOMATED PASS | `PROBE scroll from text, Close and language button: PASS` |
| 4 | A drag that starts on the **footer** (Done, the erase bar) or on the **gate card** (hold bar, Back) is inert: nothing closes, unlocks or erases; a tap on Back still works | AUTOMATED PASS | `PROBE footer and gate card swipes are inert: PASS` |
| 5 | A plain tap still presses a button, still sets a slider, Done still closes | AUTOMATED PASS | `PROBE taps still work: PASS` |
| 6 | A horizontal drag on a slider is still a slider drag (no scroll) | AUTOMATED PASS | `PROBE slider still drags: PASS` |
| 7 | **Two fingers**: while finger A scrolls, a second finger cannot start the erase hold, press Voice Off, close via Done, or move the list; A keeps scrolling and lifts clean. While A merely presses a button (in the list) or Keep my stars (in the footer), a second finger on the erase bar starts nothing and A's tap still lands | AUTOMATED PASS (was FAIL before the fix: "a second finger on the erase bar started the hold", "a second finger pressed Voice Off (1)", "a second finger on Done closed the panel") | `PROBE two fingers: PASS` |
| 8 | Done, Reset progress and the stars are on screen WITHOUT scrolling (pinned footer), the scroll area never runs under the footer, the scrollbar is >= 48 px, the last row is clear of the footer at the end | AUTOMATED PASS | `PROBE footer reachable 1334x750: PASS`, `PROBE footer reachable 2340x1080: PASS` |
| 9 | **Close** (header) closes; in overlay mode the corner gear comes back | AUTOMATED PASS | `PROBE close, Escape, Android back: PASS` |
| 10 | **Escape / `ui_cancel`**: closes the open panel; acts as Back on the pause card's gate card (`back_requested` + `closed`), on the gear-tapped card (gear comes back, host hears nothing) and on the standalone card (asks for the title); with only the gear showing it is left to the room | AUTOMATED PASS (was FAIL on both overlay cards before the fix) | `PROBE close, Escape, Android back: PASS` |
| 11 | **Android back** (`NOTIFICATION_WM_GO_BACK_REQUEST`): same as Escape, delivered with `propagate_notification` | AUTOMATED PASS for the panel's handler (was unhandled before the fix). NOT TESTABLE HEADLESS: the hardware key itself. Note `application/config/quit_on_go_back` is unset in `project.godot` (default true), so on Android the back key also quits the app after this handler runs; that is a project.godot decision outside this worktree's ownership | `PROBE close, Escape, Android back: PASS` |
| 12 | **Home from the house pause card**: a real tap on the card's Grown-ups opens the gate card over the held room (`HouseHud.is_world_paused()` true, pause card down); a 3 s hold then Done, or Back straight away, frees the overlay and gives the room back (`is_grown_ups_open()` false, `is_world_paused()` false, pause card stays down) | AUTOMATED PASS through the real `HouseHud` (no world under it) | `PROBE home from the pause card: PASS`; the same hand-off with a real `HouseWorld` (taps disabled, character disabled) is `test_interaction_ux.gd` in the suite |
| 13 | **Home from the title**: standalone panel; Back, Close (after the hold) and Done (after the hold) each ask for `main.tscn` (`is_going_home()`); the scene swap itself is skipped under a scripted tree | AUTOMATED PASS for the request. NOT TESTABLE HEADLESS: the actual `change_scene_to_file` to the title; owner: title -> Grown-ups -> Back / Done -> title | `PROBE home from the title: PASS` |
| 14 | **Music slider**: a tap on the track calls `Audio.set_music_volume_linear` at once, writes `musicVolume`, reads back after relaunch, and the reopened panel shows it (value label too) | AUTOMATED PASS (mixer through a stand-in `Audio` node; real SaveService on disk). NOT TESTABLE HEADLESS: audibility | `PROBE sliders drive the mixer and persist: PASS` |
| 15 | **Voice / Aliz / Bunny sliders**: `TtsService.set_voice_volume`, `Voice.set_character_volume("aliz" / "bunny")` at once; `voiceVolume`, `alizVoiceVolume`, `bunnyVoiceVolume` persisted and read back; the real `TtsService.get_voice_volume()` and `VoiceDirector.get_character_volume()` on fresh instances return the saved levels | AUTOMATED PASS. NOT TESTABLE HEADLESS: audibility | `PROBE sliders drive the mixer and persist: PASS` |
| 16 | **Language**: a tap on a helper-language button updates the second line under Music and Speed immediately (`Localization.helper(...)`), persists `helperLanguage` (+ `thaiHints` in step), the reopened panel after relaunch shows it selected with the same line; Off hides the lines; Thai shows the Thai privacy block, another language hides it | AUTOMATED PASS (was FAIL before the fix: the Thai privacy block only refreshed on the next open). The button tapped is the first of ja/zh/hi/ar this machine has a font for; a language with no font is offered disabled by design | `PROBE language updates and persists: PASS` |
| 17 | **AI Tutor Off/On** and **Hands-free Off**: persisted (`aiTutorEnabled`, `handsFreeMode`), shown Off after relaunch; the classroom's own reader `tutor_scene._hands_free_setting()` returns false; the title's `main.tutor_available()` goes false on Off and true on On | AUTOMATED PASS | `PROBE tutor toggles persist and the classroom reads them: PASS` |
| 18 | **Privacy information**: three static labels equal to the reviewed copy, contain verbatim "The online AI tutor is switched off in this build.", contain no `http`, `www.` or `://`, no Button/RichTextLabel inside, on screen when scrolled to | AUTOMATED PASS | `PROBE privacy information is static: PASS` |
| 19 | **Delete learning history**: first tap arms, second deletes `tutorProgress` (+ today's tutor minutes); stars stay at 3 in the profile and in the footer; status says stars are untouched | AUTOMATED PASS (behind the 3 s gate, then two taps) | `PROBE delete history and reset progress: PASS` |
| 20 | **Reset progress**: Reset swaps in the confirmation; a TAP on the hold bar erases nothing; Keep my stars cancels; a real press held 3 s erases (stars 0 in the footer, in the profile, and after relaunch) | AUTOMATED PASS | `PROBE delete history and reset progress: PASS` |
| 21 | **Gear**: a tap opens the gate card (no unlock), a wobble keeps the hold, sliding off cancels, Back returns to the gear, a 3 s hold opens, Done returns to the gear | AUTOMATED PASS | `PROBE gear tap and hold: PASS` |
| 22 | **No dead overlay**, at 1334x750, 2340x1080 (phone) and 1024x768: with only the gear showing, taps reach the world behind; the gear-tapped card, the standalone card and the pause card's card each keep Back fully on screen and let no tap around the card through; the open panel keeps Close and Done on screen at scroll 0 and Done at the end, and no tap on it reaches the world; after Done the world is live again | AUTOMATED PASS | `PROBE no dead overlay 1334x750: PASS`, `PROBE no dead overlay 2340x1080: PASS`, `PROBE no dead overlay 1024x768: PASS` |
| 23 | Parent-only actions stay behind the 3 s gate | AUTOMATED PASS: every panel action above is reached only after `_hold_for_three_seconds` on a gate, or via `open_settings()` which hosts call only from their own gated entry | `PROBE gear tap and hold: PASS`, `PROBE home from the pause card: PASS`, `PROBE home from the title: PASS`; `test_parent_gate.gd` in the suite |
| 24 | Physical multi-touch on the iPad (real `Input` ordering of two fingers, palm rejection) | NOT TESTABLE HEADLESS | Owner: open Settings, scroll with one finger while a second finger taps Voice Off / presses "Hold 3 seconds to erase"; nothing may change. The harness pushes the events in the order `Input` documents; the device is the only proof of that ordering |
| 25 | Android hardware back and `quit_on_go_back` | NOT TESTABLE HEADLESS | Owner decision: leave the default (back quits the whole app, settings included) or set `application/config/quit_on_go_back=false` in `project.godot` so back closes Settings and returns to the room. The panel handles the request either way |
| 26 | Title -> Grown-ups -> Done returns to the menu (the actual scene swap) | NOT TESTABLE HEADLESS | Owner: from the title press Grown-ups, hold 3 s, press Done; the title must come back. The request is asserted (row 13) |
| 27 | Sliders are audible at the new level; helper fonts on the device draw Thai / zh / ar / hi / ja | NOT TESTABLE HEADLESS | Owner: move Music while music plays; pick each language and read the second line under Music |

## Fixes made in this pass (`game/scenes/parent/parent_settings.gd`)

* **One finger at a time.** The gesture recogniser now remembers the touch index of the
  finger whose gesture is live and marks every touch/drag of any other index as handled
  before the GUI sees it. In Godot 4.7 a bare second-finger touch presses a `Button` and
  starts a `ParentalGate` hold (shown by the pre-fix run), so this is a real guard, not a
  cosmetic one. Presses on the open panel outside the scroll area (the footer) are tracked
  too (`Gesture.OUTSIDE`), so the rule holds while a grown-up is pressing Done, Reset or
  Keep my stars.
* **Escape / back on every card.** `request_back()` closes the open panel or acts as the
  gate card's Back whichever way the card was reached (title, pause card, gear tap);
  `ui_cancel` and `NOTIFICATION_WM_GO_BACK_REQUEST` both call it. Before, only the open
  panel and the standalone card answered Escape, and the Android request was ignored.
* **Thai privacy block follows the language at once** (it only refreshed on the next open).
* `is_going_home()` reports the title request even under a scripted tree, so the harness
  can assert Back / Close / Done ask for the title.

## Shots

Rendered by `tests/shots_settings.gd` at the pixel size named (asserted in the script):

* `docs/shots/settings_gate_ipad.png`, `docs/shots/settings_gate_iphone.png`: the standalone gate card (hold bar + Back).
* `docs/shots/settings_ipad.png`, `docs/shots/settings_iphone.png`: the panel open, scroll 0: Close in the header, Done / Reset / stars in the pinned footer, the 48 px scrollbar.
* `docs/shots/settings_bottom_ipad.png`, `docs/shots/settings_bottom_iphone.png`: scrolled to the end; Done still pinned, the last row clear of the footer.

## Not touched

`house_hud.gd`, the tutor files, the main menu, icons, `gear_visual.gd`, `project.godot`,
`cloud/`, `backend/`. The pause-card and title probes drive those hosts read-only through
their public methods.
